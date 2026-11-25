# Wasserspiegelung (mirror images in water and puddles)

Built 2026-11-15. Ellie, other players, settlers, the knight, animals, trees, bushes, rocks and
buildings show an upside-down mirror image in rivers, lakes and rain puddles.

## How it works

1. **Registration.** Things register with `WaterReflections.watch(node, moving)` in their
   `_notification(NOTIFICATION_ENTER_TREE)` and leave with `unwatch`:
   - `Interactable` (all props, `WorldProp`, `TownStructure`, settlers, Hallgrat people ...);
     `reflect_moving = true` on `Settler` and `HallgratResident` makes them "moving".
   - `Player`, `Adventurer`, `WildRabbit`, `WildCorvid` (+ owl/hoopoe), `WoodlandMammal` (+ bears),
     `RiverAnimal` (moving); `Hut`, `HallgratBuilding` (resting).
   Resting things go into a 256 px bucket grid, moving ones into a list.
2. **Choosing** (`_rebuild`, every 0.2 s). Things in the view, or up to 230 px above it, whose mirror
   image (from their waterline down, as tall as their sprites) lies on river/lake water
   (`WorldRivers.field_at`, sampled every 12 px; cached for resting things). While
   `WeatherManager.puddle` > 0.04 everything in view counts (puddles are shader noise, the CPU
   cannot know where they lie). Nearest to the view centre first.
3. **Drawing** (`RenderingServer.frame_pre_draw`, after the camera has moved). Each visible
   `Sprite2D` part is copied as a pooled RenderingServer canvas item into a SubViewport of the view's
   size: same texture frame (`get_rect`, frame coords, flips), same material (Ellie's hair, blood,
   wetness and appearance shaders stay right), transform = mirror about the waterline * the sprite's
   global transform. At most `MAX_ITEMS` (180) copies. Custom-drawn parts come from
   `reflection_painters()` (Ellie's sword arm: `AttackComponent.paint_arm`). Waterline =
   `reflection_line()` if the thing has it (Ellie: feet minus how deep she wades), else its position.
4. **Reading.** `assets/shaders/water_reflect.gdshaderinc`: globals `g_reflect` (the SubViewport
   texture), `g_reflect_rect` (its world rect), `g_reflect_on`. `reflect_at(px, wobble, t)` slides
   rows sideways in whole pixels (ripples); `reflect_tint` cools and darkens.
   - `river_water.gdshader`: calm lakes mirror clearly, rivers more broken, rain and storm roughen
     it, ripple crests cut thin gaps; foam, glints, rain rings and swimmer rings stay on top.
   - `ground_tone.gdshader`: rain puddles are small, still mirrors.

## Night sky in the water

Built 2026-11-15. At night rivers and lakes mirror the sky: `assets/shaders/night_sky.gdshaderinc` (`night_sky_at`), added by
the unlit, additive night pass `river_glow.gdshader` (the world-lit water would be swallowed by the night tint).

- **Anchored to the world, independent of Ellie:** stars, the Milky Way, the moon and its glade stay anchored in world
  space (on a periodic world sky tile for the moon) so none of them slide along with Ellie as she moves; they drift only
  slowly over the night and shimmer with ripples. Globals `g_sky_view` (view rect) and `g_sky` (x night run dusk 0 .. dawn 1,
  y moon phase, z sky strength, w moon brightness) are pushed by `NightAtmosphere` (`_push_sky`, `_push_transform`).
- **Moon:** drifts east to west over the night across each world sky tile; its real phase (`TimeManager.moon_phase`,
  eight days; the reflection is upside down), dark seas, limb darkening, earthshine on the dark part, a dithered halo. Its rows slide
  with the ripples.
- **Glade:** below (and a little above) the moon the water breaks the light into short bright dashes in rows that drift sideways;
  calm lakes keep it short and narrow, rivers, rain and storm throw it long and wide.
- **Stars:** one candidate per 5x5 world px, most faint, a few bright with a cross on calm water or smeared on choppy water, white,
  blue or warm; a faint Milky Way band with dark lanes; the sky turns slowly over the night independently of the camera; crests make stars wink.
- Clouds (`cloud_thick`, thin veils let stars through), storm and fog hide the sky; mirror images of trees/people/houses cover it.
  Deep water mirrors more than shallow water. By day (`g_sky.z` 0) the pass returns at once.
- Look: `tools/preview_world_rivers.tscn -- --lake=1 --sky --night --day=4 --weather=clear --capture=/abs.png`
  (`--day=2` half moon, `--time=T`, `--zoom=Z`, `--weather=ID`). Picture `docs/img/wasserspiegelung_nacht.png`.

## Rules

- Left out: sprites named `*shadow*`, `*decal*`, `SwimUnder` (under the surface), sprites with a
  negative z (ground pieces), procedurally drawn things. **Shadow creatures have no mirror image**
  (their rigs are drawn, not sprites; fitting: the void throws none).
- Nested registered things (a door on a hut) are their own entries, not part of the parent's image.
- A thing's own fade (a tree turning see-through for a player behind it) does not fade its mirror image.
- Nothing on water in view: the SubViewport does not render and the shaders skip the lookup
  (`g_reflect_on` 0). Settings: SPIEL/GRAFIK -> WASSERSPIEGELUNG (`reflections`, default on).
- Cosmetic and local: every peer mirrors what it sees, nothing is synced or saved.

## Checks

- Look: `Godot --rendering-driver opengl3 --path . tools/preview_world_rivers.tscn -- --lake=1 --mirror [--night] --capture=/abs.png`
  (Ellie on a lake's north shore).
- Test: `Godot --headless --path . tools/test_reflections.tscn` (prints `REFLECTIONS OK`).

## Not built

- Yard puddles baked into ground decals (only rain puddles mirror).
- A fade of the image with distance below the waterline; the night sky in rain puddles (only rivers and lakes show it).
