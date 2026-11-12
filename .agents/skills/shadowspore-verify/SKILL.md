---
name: shadowspore-verify
description: >-
  Runs Godot headless checks, automated test scenes (tools/test_*.tscn), and
  preview captures to verify Shadowspore changes. Use after editing GDScript,
  scenes, data JSONs, or art scripts.
---

# Shadowspore Verification Workflow

## 1. Headless Compile & Type Check
Because `untyped_declaration=2` (error) is enabled in `project.godot`, always verify script compilation first:
```bash
godot --headless --path . --quit
```
*(If `godot` is not in `PATH`, use the configured Godot 4.7 binary path.)*

## 2. Run Relevant Test Scenes
Run the matching test scene(s) under `tools/test_*.tscn`:
```bash
godot --headless --path . res://tools/test_<feature>.tscn
```

**Important timing rules:**
- **Deterministic frame tests** (e.g., `tools/test_wisp.tscn`, `tools/test_crow_hoard.tscn`): pass `--fixed-fps 60`.
- **Real-time timer tests** (e.g., `tools/test_magic.tscn`): run **without** `--fixed-fps`.

## 3. Visual Capture Check (UI / Art / Shaders)
For visual changes, capture frames using `tools/preview_*.tscn`:
```bash
godot --path . res://tools/preview_<feature>.tscn -- --dir=<abs_output_dir>
```
Inspect the resulting PNGs with `read_file` before reporting completion.
