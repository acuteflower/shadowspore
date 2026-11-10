# Lichtfischer (Light Fisher) – fourth standard shadow creature, first of the water

*Light is a lie.* By night only a pale lantern on a stalk shows above the water, a cold teal light that looks like a lamp of the town or a glowing plant at the bank. Whoever
steps up to it is bitten. Under the surface lies a long black body with a hinged double jaw of glass needles and a throat that burns violet-magenta.

Code: `src/entities/enemies/light_fisher.gd/.tscn` (state machine, senses, attacks, replication), `fisher_rig.gd` (100 % procedural pixel rig, no sprites), `fisher_hurtbox.gd`
(lantern vs. maw), `src/fx/fisher_dazzle.gd` (local screen dazzle). Data `data/enemies.json` `light_fisher`, night source `data/night.json` `water`.
Sounds `py -3 tools/audio_fisher.py` (ten synthesised placeholders `assets/audio/fisher_*.wav`). Contact sheet `docs/img/fisher_poses.png`
(`Godot --rendering-driver opengl3 --path . tools/preview_fisher.tscn -- --capture=/abs.png [--day] [--closeup=N]`). Test `tools/test_fisher.tscn` (38 checks, `--fixed-fps 60`).

## Look
- Shared shadow-creature standard: black world-lit flesh (`040208`–`261a4a`), violet rim, magenta eyes, veins through `VoidGlow` (the heartbeat runs up the stalk into the lantern).
- The lantern is teal (`7fe8d0`) in a cage of glassy ribs; a faint **reflection** hangs in the water and a few **false lamps** (fake glow-cap lights) flicker beside it.
  When it attacks the lie breaks: the bulb turns white with a magenta rim, the cage opens like a flower.
- Under water: a dark wobbling silhouette with dorsal spines that breaks the surface only for a bite (foam, spray, ripple rings).
- Everything is pose-driven (`FisherRig.Pose`), so every peer draws the same from the replicated state.

## Behaviour (host decides, peers replay)
| State | What happens |
|---|---|
| LURK | drifts slowly in deep water, the lantern bobs and twitches now and then (bait that looks alive) |
| NOTICE → STALK | hears (walking 120 px, sprinting 190, swimming 215, sneaking 38, swings 175; **day ×0.6**) or sees (150 px); swims to the water nearest the target, never leaves the water, lantern hangs towards the target |
| SCHNAPPLUNGE | `SNAP_WINDUP` 0.7 s (the bait dips and goes dark, red flowing-pixel fan on the surface, aim locks 0.3 s before release) → `SNAP` 0.24 s (head breaks the surface, glass jaws clamp, 20 damage and a **pull of 26 px towards the water**) → `GAPE` 0.95 s (hangs open: **soft**, maw takes ×1.6) |
| BLENDLICHT | lantern swells (0.85 s, red disc of 72 px), bursts: ring of cold light, 6 damage, **local screen dazzle** (white-out + five false teal lamps, `FisherDazzle`); a target still in reach gets the **Blendbiss** (short 0.45 s windup) |
| IRRLICHTER | three lantern sparks drift out and **settle around the target** after a long flight (60 px/s, deterministic arcs), each bursts in a 14 px disc for 8 damage: stand still and they land on you |
| DIVE / SURFACE | at 66 % and 33 % health, after 3 lantern hits and when cornered it sinks and comes up 70–140 px away |

**Weak point:** the lantern (×1.5, a blow on it **breaks a casting**); the maw is only a target during the bite (`GAPE` ×1.6 and it flinches). A sweep that touches both counts once
(`LightFisher.accept_hit`).

## World rules
- Water only. `WorldLevel.water_depth(point)` (-1 on land and unloaded ground, otherwise depth / swimming depth, from `WorldRivers.depth_amount`; rivers and lakes). It has no body
  collision, steers by probes (`_water_dir`) and its line-of-sight rays ignore the river's own deep-water colliders (group `river_depth`).
- **F5** (`debug_spawn_fisher`, `InputManager.debug_fisher_pressed`; F4 is the clock) spawns one at the nearest deep enough water to the cursor, nothing happens away from water.
  `TestLevel.water_depth` is -1 in the arena, so there it never spawns.
- Night: `NightDirector._try_water` (data `night.json` `water`): from day 1, level 2, budget ≥ 6, 45 % per attempt every 8 s, at most 2 per group and 4 in total, born in deep water 10–40
  tiles from a player, outside the town's light and not within 9 tiles of anybody (it rises with the lantern unfurling). It spends 2.0 of the group budget, a kill refunds 50 %, a creature
  left behind goes home with its budget back, at dawn `retire()` sinks it without loot. It does not use `NightBehavior` (no raids, it fishes where it was born).
- Loot: 18 XP, 6–12 copper, `void_splinter` 70 %, `glow_cap` 50 %, `shadow_core` 14 %. Footprints: `ShadowTrailComponent` scaled 1.3, an infestation patch on the water edge at death.

## Not built (ideas)
Fishing-line interaction (a hooked Lichtfischer taking the float), a dedicated lure item, river-animal fear of it, night glints on the lantern reflection tied to the town lamps.
