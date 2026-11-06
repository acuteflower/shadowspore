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
