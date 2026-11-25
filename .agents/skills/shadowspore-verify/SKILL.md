---
name: shadowspore-verify
description: >-
  Runs Godot headless checks, Python v2 atlas/zone validators, automated test
  scenes (tools/test_*.tscn), and preview captures to verify Shadowspore
  changes. Use after editing GDScript, scenes, data JSONs, or art scripts.
---

# Shadowspore 2.0 Verification Workflow

## 1. Headless Compile & Type Check
Because `untyped_declaration=2` (error) is enabled in `project.godot`, always verify script compilation first:
```powershell
godot --headless --path . --quit
```
*(If `godot` is not in `PATH`, use the configured Godot 4.7 binary path. After adding/deleting assets or scripts, run `--import` once before `--quit`.)*

## 2. World Atlas & Zone Validators (Python)
After editing `data/world/**` or world-generation tools (`build_altmark_world.py`, `paint_zone_map.py`):
```powershell
py -3 tools/check_atlas.py
py -3 tools/check_zone.py windkap
```

## 3. Run Relevant Test Scenes (`tools/test_*.tscn`)
Run the matching test scene(s) under `tools/test_*.tscn`:
```powershell
godot --headless --path . res://tools/test_<feature>.tscn
```

### Canonical v2 Test Suites
- **ZoneWorld, Atlas & Nature:** `test_atlas`, `test_zone_lab`, `test_zone_director`, `test_water_v2_e2e`, `test_living_tree`, `test_living_rock`
- **Movement, Combat & Boss/Enemy:** `test_movement_2_0`, `test_finisher`, `test_slash_world_fx`, `test_spider_v2`, `test_heavy`, `test_shadow_step`, `test_grip`, `test_magic`, `test_zero_g`, `test_swim`
- **Dungeons & Core Systems:** `test_dungeon_rules`, `test_dungeon_combat`, `test_dungeon_ui`, `test_starhall`, `test_autosave`, `test_cloud_save_coercion`, `test_pets`, `test_potions`, `test_fishing`, `test_mine_generator`, `test_root_weave`, `test_star_mirror`, `test_town_rules`
- **HUD, Chat & Menus:** `test_hud_layout`, `test_hud_profile`, `test_boss_hud_hide`, `test_hotbar_fold`, `test_chat`, `test_mod_menu_v2`, `test_main_menu`, `test_loading_start`, `test_pause_sidebar`

**Important timing rules:**
- **Deterministic frame tests:** pass `--fixed-fps 60`.
- **Real-time timer tests** (e.g., `tools/test_magic.tscn`): run **without** `--fixed-fps`.

## 4. Visual Capture Check (UI / Art / Shaders)
For visual changes, capture frames using `tools/preview_*.tscn`:
```powershell
godot --path . res://tools/preview_<feature>.tscn -- --dir=<abs_output_dir>
```
Inspect the resulting PNGs with `read_file` before reporting completion.
