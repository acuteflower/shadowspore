# Runtime performance

World streaming prepares one detached chunk incrementally in `WorldLevel.ChunkBuild`.
`STREAM_BUDGET_USEC` gives preparation a cooperative 2 ms budget each frame; individual
work units may run longer. Ground, collision, props and decorative plants enter the
live world together at commit. Wildlife is notified only after activation.

Initial loading, editor rebuilds, a player's missing destination chunk and chunks
intersecting the view (plus 64 px) finish synchronously. These safety paths can still
exceed the budget so teleports and viewport changes cannot expose partial terrain.
Abandoned jobs and editor snapshots discard detached nodes before reusing map data.

`PropGenerator.Query` resolves the normal prop window and its five-tile decorative
margin together. Candidate membership bits preserve each original query's exact
neighborhood, priority rules and iteration order. Decorative plant obstruction uses
spatial buckets of obstacle discs and the original exact distance test. It includes
unloaded neighbors and moved/scaled authored props. Random streams are unchanged.

`PixelText` caches untextured meshes for up to 512 normalized labels. Text keeps the
same pixel quads and the four separate outline passes, including alpha overlap and
scaled rendering. Each canvas retains meshes in its last draw even if the shared
cache evicts them. Clock geometry/day-profile and glow scanline widths are also
cached; animation clocks and redraw frequency are unchanged.

Run regressions with the project's Godot binary:

```sh
Godot --path . tools/test_streaming_performance.tscn
Godot --path . tools/test_world_editor.tscn
Godot --path . tools/test_story_start.tscn
Godot --headless --path . tools/test_enemy_navigation.tscn
Godot --path . tools/test_wind.tscn
```

The streaming test reports preparation/commit timings and checks atomic activation,
identical synchronous/incremental results, authored transforms, cancellation,
teleport fallback, editor invalidation and bounded text caching. Timings depend on
the machine and renderer; they are diagnostics, not assertions about FPS.

## Grafikstufen (`Quality`, src/autoload/quality.gd)

Autoload `Quality` hält die gewählte Stufe (`level`: NIEDRIG / MITTEL / HOCH / ULTRA) und die
wirksame Stufe (`effective`). HOCH ist der bisherige Look; jede Stufe ist ein Satz Budgets in
`Quality.PRESETS`, die Systeme über `Quality.get_value(key)`, `Quality.scale(key)` und
`Quality.scaled(n, key, min)` lesen (Signal `changed`). Heiße Pfade bekommen statische Werte
(`apply_static`: `RigClock.base_hz/base_fast_hz`, `NightLight.limit/small_min/breath_step`).

| Schlüssel | wirkt auf |
|---|---|
| `rig_hz`, `rig_fast_hz` | Neuaufbau der prozeduralen Gegner-Rigs (`RigClock`) |
| `lights`, `lights_small_min`, `light_breath_hz` | gleichzeitige Hardware-Lichter (`NightLight.budget`), Atemtakt |
| `fireflies`, `particles` | Glühwürmchen; jeder neue Partikel-Emitter (`node_added`) |
| `wildlife` | alle Tier-Obergrenzen (`max_loaded`, Flussfauna `max_total`), nur der Host entscheidet |
| `reflections`, `reflection_items`, `shadow_items` | Wasserspiegelung an/aus und Kopien-Budget, Sonnenschatten-Budget |
| `weather_fx` | Obergrenze der Wetter-Effekte (zusätzlich zur eigenen Einstellung) |
| `tree_cover_hz`, `sway_hz` | Baum-Verdeckungstest, Takt des Wind-Schwankens |
| `stream_usec`, `prefetch` | Chunk-Streaming-Budget pro Frame, vorgezogene Worker-Jobs |
| `pixel_res` | NIEDRIG: das Bild wird in 640x360 gerendert und hochskaliert (`CONTENT_SCALE_MODE_VIEWPORT`) |

Einstellungen (`GameSettings`): `quality` (-1 = beim ersten Start `Quality.detect()`: GPU-Typ,
Kerne, RAM), `adaptive` (Governor an), `fps_cap` (Index in `FPS_CAPS`, letzter = offen),
`pixel_res` (Pixel-Auflösung auch auf höheren Stufen). Menüs: Hauptmenü EINSTELLUNGEN → BILD und
Pausenmenü EINSTELLUNGEN; `Quality.cycle/label` teilen die Logik.

**Governor:** alle 2,5 s mittlere Framezeit gegen das Ziel (Bildratenlimit, sonst
Bildschirmfrequenz 60-144 Hz). Mehr als 18 % drüber → eine Stufe runter; 12 s am Stück unter
62 % → eine Stufe hoch (nie über die gewählte). 6 s Pause nach jeder Änderung. Nichts davon wird
gespeichert; `pixel_res` folgt nur der gewählten Stufe (kein plötzlicher Bildwechsel).

**Threads:** `Jobs.max_running` = Kerne minus 3/2/2/1 (NIEDRIG..ULTRA), höchstens 8 (ULTRA 12).

Kommandozeile: `-- --quality=0..3` erzwingt eine Stufe, `--quality-fixed` schaltet den Governor ab
(Headless läuft immer fest). Benchmark: `Godot --path . tools/bench_world.tscn -- --quality=N
[--quick] [--probe]` druckt jetzt auch Render-CPU- und GPU-Zeit.
