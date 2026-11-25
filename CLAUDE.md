# Shadowspore 2.0 — Developer Reference

**Shadowspore** ist ein 2D-Pixel-Art-Top-Down-(3/4)-Action-RPG (Erkundung, Kampf, Nacht-Survival, Dorfaufbau, Farming, Magie, Alchemie, Dungeons) in **Godot 4.7 (GDScript)** für **1–4 Spieler** (host-authoritativ).
Seit Version 2.0 nutzt das Spiel die **Zonenwelt- & Atlas-Architektur** (`ZoneWorld`, Kontinent **ALTMARK**, Startzone **WINDKAP**, `SaveGame.VERSION = 2`).

---

## 1. Harte Projektregeln

- **Strikte statische Typisierung überall** (`gdscript/warnings/untyped_declaration=2` in `project.godot`). Jede Variable, jeder Parameter und jeder Rückgabewert muss typisiert sein.
- **Multiplayer-first, host-authoritativ:** Singleplayer = lokaler ENet-Host mit 1 Spieler (`NetworkManager.host_singleplayer()`). Zustandsänderungen laufen per `@rpc` auf dem Server (`if not multiplayer.is_server(): return`). Dynamische Entities nutzen `MultiplayerSpawner` + `MultiplayerSynchronizer`. Online-Koop nutzt Nakama-Relay (`src/net/`).
- **Input nur über `InputManager`:** Niemals `Input.is_key_pressed` in Entities; nur definierte Input-Actions (`move_left/right/up/down`, `sprint`, `shadow_step`, `blink`, `sneak`, `interact`, `action_primary`, `action_secondary`, `inventory`, `map`, `dungeons`, `skills`, `progress`, `quest_journal`, `hotbar_1..8`, `build*`, `fish_*`, `pet_whistle`, `freecam`, `mod_menu`) und `InputManager.aim_vector()`.
- **Datengetrieben:** Statische Spieldaten liegen in `res://data/*.json` (Top-Level via `DataRegistry.table(name)`) sowie verschachtelt in `res://data/world/**` (via `DataRegistry.json(rel_path)`).
- **Komposition:** Flache `.tscn`-Szenen, zusammengesetzt aus kleinen Komponenten in `src/components/` (`HealthComponent`, `HitboxComponent`, `HurtboxComponent`, `VelocityComponent`, `InventoryComponent`, `LocomotionComponent`, `SwimComponent`, `AgileTraversal`, `WallClimb`, `FinisherComponent`, `ZeroGComponent`, `DungeonProfileComponent`, …).
- **Rendering & Koordinaten:** `640×360` Basis-Viewport, `16×16` Tiles, Nearest-Filtering, `canvas_items` + `expand`. Welt-Entities nutzen `y_sort_enabled = true` mit Pivot unten-Mitte (Füße).
- **Beleuchtung & Unlit:** Alles, was nachts hell bleiben muss (Texte, Balken, Warnzonen, Loot, Münzen, Glow-Layer, Runen), nutzt `Unlit.material()` oder `render_mode unshaded`. Punktlichter nutzen `NightLight` / `LightTexture.apply()`.
- **Multithreading (`Jobs` Autoload):** Schwere Hintergrundarbeit über `Jobs.run(work, on_done, ...)` (`on_done` läuft auf dem Main-Thread). In Worker-Funktionen **nur** unveränderliche/gesperrte Daten lesen — **niemals** Nodes einhängen, `get_tree()` rufen, Tree-Signale emittieren oder geteilte Dicts/Arrays mutieren. Szenen/Skripte vorher per `Jobs.warm()` auf dem Main-Thread vorladen.
- **Physik-Layer:** `1` world · `2` player · `3` enemy · `4` hitbox · `5` hurtbox (Gegner, Dummies) · `6` player_hurtbox.

---

## 2. Projektstruktur & Autoloads

### Autoloads (`project.godot`)
`EventBus` · `DataRegistry` · `Jobs` · `NetworkManager` · `TimeManager` · `InputManager` · `Terrain` · `GameCursor` · `Quality` · `CloudSession` · `Chat` · `GameGuard`

### Verzeichnisse
- `src/world/v2/` — Zonenwelt-Engine (`ZoneWorld`, `ZoneDirector`, `ZoneStage`, `ZoneCoop`, `ZoneMood`, `ZoneBackdrop`, `ZoneVeil`, `ZoneMath`, `Landscape`, `WindkapProps`)
- `src/world/` — `Atlas`, `PocketSpace`, `GameLauncher`, `Main`, `DayNight`, `DaylightField`, `SunShadows`, `WeatherManager`, `NightDirector`, `WorldWind`, `GroundSurfaces`, `LivingGrass`, `RockyGround`, `Interiors`, `StarHallRoom`, `Puzzles`, `TrialLevel`, `TestLevel`, `FreeCam`, `dungeons/`, `mine/`, wiederverwendbare Hallgrat-/Relief-/BiomeBlend-/DesertRuins-Module
- `src/water/` — Wasser 2.0 (`WaterField`, `WaterReflections`, `RiverFauna`, `RiverAnimal`, `WorldRivers`-Query-Interface)
- `src/entities/` — `player/`, `enemies/` (inkl. `desert_boss/`, `witch_boss/`), `npcs/`, `props/` (inkl. `LivingTree`, `LivingRock`, `ShadowFruitArt`, `VeilThreadPickup`), `drops/`, `magic/`, `puzzles/`, `wildlife/`, `wonders/`
- `src/components/` — Wiederverwendbare Entity-Komponenten
- `src/systems/` — Regel- & Persistenzmodule (`SaveGame`, `MovementRules`, `FinisherRules`, `HeavyRules`, `SpellRules`, `AlchemyRules`, `DungeonRules`, `ResonanceRules`, `MapDiscovery`, `Waystones`, `VeilThreads`, `GoddessSystem`, `ShaderPrewarmer`, `MusicDirector`, …)
- `src/town/` — Dorfaufbau, Siedler, Farm, Karawane, Questtafel (`TownManager`, `FarmManager`, `CaravanManager`, `BoardManager`, … — vorbereitet für *Glimmrast* in ALTMARK)
- `src/ui/` — HUD v2 (`HudDirector`, `HudNotices`, `HudText`, `WayVine`, `CompanionVine`, `ZoneArrival`, `GameChat`), 4-Ebenen-Atlas (`MapWindow`, `AtlasView`, `AtlasBook`, `MapMarkers`), Menüs (`MainMenu`, `MenuWorld`, `PauseMenu`, `DungeonWindow`, `GoddessWindow`, `InventoryWindow`, `QuestJournal`, `SkillTreeWindow`, `ProgressWindow`, `ModMenu`, …)
- `src/fx/`, `src/net/`, `src/fishing/`
- `data/` — Flache JSON-Tabellen (`items`, `enemies`, `spells`, `alchemy`, `finishers`, `movement`, `dungeons`, `shadow_fruits`, `hud`, `zero_g`, …)
- `data/world/` — v2-Atlas (`atlas.json`, `moods.json`, `continents/{main,lab}.json`, `thresholds_*.json`, `landscape/*.json`, `continents/baked/`, `zones/<id>/{zone.json,baked/}`)
- `tools/` — Python-Art-/Audio-Generatoren (`art_*.py`, `audio_*.py`), v2-Welt-Pipeline (`build_altmark_world.py`, `paint_zone_map.py`, `check_atlas.py`, `check_zone.py`), Godot-Tests (`test_*.tscn`) & Previews (`preview_*.tscn`)
- `docs/` — Aktuelle Design- und Konzeptdokumente (mit `.gdignore`, damit Godot `docs/img/` nicht importiert)

---

## 3. Shadowspore 2.0 — Kernarchitektur & Systeme

### 3.1 Zonenwelt, Kontinent ALTMARK & PocketSpace
- **Hauptwelt-Szene:** `res://src/world/v2/zone_world.tscn` (`ZoneWorld`, gestartet über `GameLauncher` → `Main`).
- **Atlas-Modell (`src/world/atlas.gd`):** Lädt `data/world/atlas.json`, Kontinente (`main` = **ALTMARK**, `lab` = Labor-Testkontinent), Schwellen (`thresholds_*.json`) und Zonen (`data/world/zones/<id>/zone.json`).
- **ALTMARK (11 Zonen in 5 Regionen):**
  - *Südwestküste:* `windkap` (Startzone, voll ausgebaut), `klippenstieg`, `suedkap` (Sturmhafen)
  - *Grünland:* `erlenfurt`, `muehlenaue`, `glimmrast`
  - *Glaskamm:* `hallgrat`, `kristallgrat`
  - *Hexenwald:* `hexenwald_saum`, `hexenwald_kern`
  - *Leerenblühen:* `varnholm`
- **Multi-Zone-Coop (`ZoneDirector`, `ZoneStage`, `ZoneCoop`):** Mehrere Zonen laufen parallel auf räumlich getrennten Stages; bis zu 4 Spieler können unabhängig in verschiedenen Zonen sein. Jeder Spieler sieht seine aktive Stage inkl. `ZoneBackdrop` (Fernblick `far.png`), `ZoneVeil` (Übergangs-Schleier) und `ZoneMood`.
- **PocketSpace (`src/world/pocket_space.gd`):** Deterministischer Koordinaten-Allocator für isolierte Taschenräume innerhalb von `ZoneWorld`: Innenräume (`INTERIOR`), Minen (`MINE`), Sternensaal (`STAR_HALL`), Prüfungen (`TRIAL`) und Dungeons (`DUNGEON`).
- **Speicherstand (`SaveGame.VERSION = 2`):** Speichert Spieler-Zone, Zonen-Zustände, Inventare, Entdeckungen, Wegsteine, Schattenfrüchte/Schleierfäden, Quests, Skills, Talismans, Haustiere, Sternensaal, Dungeon-Resonanz und Cloud-Sync (`CloudSession`).
- **Welt-Pipeline:** `py -3 tools/build_altmark_world.py` (Geologie, Relief, Küste, 11 Zonen) → `py -3 tools/paint_zone_map.py` (Karten/Normalen/Fernblick/Steinsetzer-Relief) → `py -3 tools/check_atlas.py` & `py -3 tools/check_zone.py <id>`.
- **Doku:** [`docs/v2_zonenwelt_atlas_konzept.md`](docs/v2_zonenwelt_atlas_konzept.md)

### 3.2 4-Ebenen-Atlas & Chronik
- **`MapWindow` (`src/ui/map_window.gd`)** delegiert die gesamte Kartendarstellung an **`AtlasView` (`src/ui/atlas_view.gd`)**, **`MapMarkers` (`src/ui/map_markers.gd`)** und das aufklappbare Buch **`AtlasBook` (`src/ui/atlas_book.gd`)**.
- **4 Zoom-Ebenen:** `ZONE` (4 px/Tile Detailkarte) → `REGION` → `CONTINENT` (1 px/Tile ALTMARK + Steinsetzer-Gravur) → `WORLD` (Weltmeer & Kontinente).
- **Entdeckung & Orientierung:** `MapDiscovery`, `Waystones` (Schnellreise), `Vistas` (Aussichtspunkte), `VeilThreads` / **Schattenfrüchte** (`ShadowFruitArt`, `VeilThreadPickup`, `data/shadow_fruits.json` — prozedurale lebendige Schattenfrüchte mit 5 Farbfamilien, akustischer/Sporen-Fährte & Archetypen).
- **Doku:** [`docs/v2_zonenwelt_atlas_konzept.md`](docs/v2_zonenwelt_atlas_konzept.md), [`docs/schattenfruechte_und_menue_konzept.md`](docs/schattenfruechte_und_menue_konzept.md), [`docs/waystones.md`](docs/waystones.md)

### 3.3 HUD v2 & UI
- **`HudDirector` (`src/ui/hud_director.gd`):** Zentrale HUD-Regie mit Profilen (Erkundung, Kampf, Boss-Fokus, Dialog, Foto/FreeCam), kollabierbarer Hotbar, `WayVine` (Kompass-/Weg-Ranke), `CompanionVine` (Koop-Mitspieler), `ZoneArrival` (Zonen-Ankunftstitel), `HudNotices` (gestaffelte Benachrichtigungen), `HudText`, `GameChat` (`Chat` Autoload).
- **Boss-HUD:** `BossBar` (mehrstufige HP-Schichten + Taumelbalken), `BossIntro`, `BossAura`, `BossPhaseScreen`.
- **Menüs & Tools:** `MainMenu` + `MenuWorld` (Startbildschirm-Szene), `PauseMenu` + `PauseSocialSidebar`, `ModMenu` (`F2` / Entwickler- & Test-Menü), `FreeCam` (`F8`), `DungeonWindow` (Steinsetzer-Prüfungstafel).
- **Doku:** [`docs/hud_v2_konzept.md`](docs/hud_v2_konzept.md), [`docs/hauptmenue_konzept.md`](docs/hauptmenue_konzept.md), [`docs/loading_screen.md`](docs/loading_screen.md)

### 3.4 Bewegung, Kampf, Finisher v2 & 3D-Griff-System
- **Movement 2.0 (`MovementRules`, `LocomotionComponent`, `AgileTraversal`, `WallClimb`, `LivingCamera`):** Taktiler Sprint-Antritt, Corner-Smoothing, 180°-Pivot, Hang-/Straßen-Physik, ausdauerschonender Reisetritt auf Wegen, Vault über Stämme/Zäune, Ledge Hop, Klettern, Kampf-Fußarbeit, 20-Hz-Koop-Glättung.
- **3D-Griff-System (`WeaponGrip`, `Arm3D`, `data/grips.json`, `data/hero_arm3d.json`):** Echte 3D-Waffen- & Werkzeugführung mit 2-Knochen-Pixel-Arm, Feder-Trägheit und pixelgenauer Arm-Verdeckung.
- **Nahkampf, Wuchtschlag & Finisher v2 (`HitScan`, `HeavyRules`, `FinisherComponent`, `FinisherRules`, `FinisherStage`, `SlashWorldFx`):** 5-Treffer-Kombo, aufladbarer Wuchtschlag, Schattenschritt/Lichtschritt (`shadow_step` / `blink`), 3-stufige Finisher (u. a. *Abgrund-Pfähler*) und persistente Welt-Schnittspuren.
- **Schattenspinne 2.0 (`ShadowSpider`):** Sichtkegel, Erschütterungs-Sinne, Haltungssystem, Backstep, Gift-Sprung & 3 Varianten.
- **Magie, Alchemie, Talismans, Skills & Veredelung:** 5 Elementarschulen (`SpellRules`, `data/spells.json`), Trankbrauen (`AlchemyRules`, `data/alchemy.json` — ersetzt früheres Kochen vollständig), `TalismanRules`, `SkillTreeWindow`, `RefineRules` (+1 bis +15), `Levels` & `LevelRewards`.
- **Doku:** [`docs/movement_2_0_konzept.md`](docs/movement_2_0_konzept.md), [`docs/finisher_v2_konzept.md`](docs/finisher_v2_konzept.md), [`docs/griff_system.md`](docs/griff_system.md), [`docs/heavy_attack.md`](docs/heavy_attack.md), [`docs/magie_konzept.md`](docs/magie_konzept.md), [`docs/alchemie_konzept.md`](docs/alchemie_konzept.md), [`docs/faehigkeiten_kampf_konzept.md`](docs/faehigkeiten_kampf_konzept.md)

### 3.5 Lebendige Natur 2.0 & Wasser 2.0
- **Boden & Bewuchs:** `GroundSurfaces` (`ground_surfaces.gdshader`), `LivingGrass` (reaktives Gras mit Wind & Verdrängung), `RockyGround` (`rocky_ground.gdshader`), `LivingTree` (Taleeiche, Silberbirke, Wildapfel — Stockausschlag, Schüttel-Ernte, Sitzwurzeln), `LivingRock` (mehrstufig abbaubare Felsen).
- **Wasser 2.0 (`src/water/water_field.gd`):** Zonen-Wasserfelder (`water_v2_surface.gdshader`, `water_v2_glow.gdshader`, `ocean_horizon.gdshader`) mit Brandung, Strandpfützen, Gezeitentümpeln, Strömung, Nacht-Biolumineszenz, `WaterReflections` (Echtzeit-Spiegelungen inkl. Sternenhimmel), `SwimComponent` (Schwimmen/Tauchen), `FishingComponent` (Angeln) und `RiverFauna` (über `WaterFieldRiversAdapter` an `WorldRivers` angebunden).
- **Atmosphäre & Beleuchtung:** `DayNight` (40-Min-Zyklus), `DaylightField` (Baumkronen-Deckung), `SunShadows` (Echtzeit-Sonnen-/Mondschatten), `WeatherManager` (10 Wetterfronten, Wolken, Gewitter, Regenpfützen), `NightDirector` & `NightAtmosphere` (Nacht-Gegner: *Leerenbrecher*, *Lauscher*, *Lichtfischer*, *Leerenschleicher*).
- **Doku:** [`docs/tageslicht_art_direction.md`](docs/tageslicht_art_direction.md), [`docs/sonnenschatten.md`](docs/sonnenschatten.md), [`docs/wasserspiegelung.md`](docs/wasserspiegelung.md), [`docs/schwimmen_konzept.md`](docs/schwimmen_konzept.md), [`docs/wetter_konzept.md`](docs/wetter_konzept.md), [`docs/nacht_atmosphaere.md`](docs/nacht_atmosphaere.md)

### 3.6 Caelia, Sternensaal, Zero-G & Dungeon-System
- **Göttin Caelia & Sternensaal (`GoddessSystem`, `StarHallRoom`, `ZeroGComponent`, `ZeroGRules`, `interstellar_cosmos.gdshader`):** Rettung vor dem ersten tödlichen Treffer, `LICHTSCHRITT`-Läuterung, schwerelose kosmische Bewegung (`ZeroGComponent`), Sternerz-Meilensteine & Sternengaben (`GoddessWindow`).
- **Dungeons (`src/world/dungeons/`, `DungeonRules`, `ResonanceRules`, `DungeonWindow`, `DungeonHud`, `DungeonResultWindow`):** Handgebaute instanziierte Szenen in `PocketSpace.Lane.DUNGEON`, 4 Archetypen (`swarm`, `expedition`, `arena`, `guardian`), 3 Gruppen-Schleierfunken, tägliche Schleierresonanz + Ruhebonus, Klangkonter & Taumel-Prüfung.
- **Doku:** [`docs/caelia_interstellar_konzept.md`](docs/caelia_interstellar_konzept.md), [`docs/sternensaal_konzept.md`](docs/sternensaal_konzept.md), [`docs/goettin_konzept.md`](docs/goettin_konzept.md), [`docs/dungeon_konzept.md`](docs/dungeon_konzept.md)

### 3.7 Weitere aktive & für ALTMARK-Zonen vorbereitete Module
- **Aktiv & wiederverwendbar:** `Interiors` (begehbare Häuser), `MineManager` (prozedurale 15-Ebenen-Mine), `Puzzles` & `TrialLevel` (Welt-Rätsel: Irrlichtspur, Hortkrähe, Wurzelgeflecht, Sternenspiegel, Prisma-Siegel), `PetRegistry` (Haustiere), `LootChests` (Wurzelkiste, Mondsiegeltruhe, Glutreliquiar), `QuestJournal` & `TrackedQuests`, `SalonWindow` (Ellie-Cosmetics & Frisuren).
- **Vorbereitet für kommende ALTMARK-Zonen:** `src/town/` (Dorfaufbau, Siedler, Farm, Karawane Jorun, Questtafel → *Glimmrast*), `src/world/hallgrat*.gd` (Stadt-System & Bewohner → *Hallgrat*), Bosse `Mornath` (Sky Cleaver), `Morwenna` (Spiegelhexe) & `Aurelith` (Herz des Sonnenquarzes).

---

## 4. Verifikation & Workflows

### Godot 4.7 Headless Compile-Check
```powershell
& "C:\Users\levin\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --quit
```

### v2 Atlas- & Zonen-Prüfung (Python)
```powershell
py -3 tools/check_atlas.py
py -3 tools/check_zone.py windkap
```

### Automatisierte Godot-Tests (`tools/test_*.tscn`)
- **Welt & Atlas:** `test_atlas`, `test_zone_lab`, `test_zone_director`, `test_water_v2_e2e`, `test_living_tree`, `test_living_rock`
- **Kampf & Bewegung:** `test_movement_2_0`, `test_finisher`, `test_slash_world_fx`, `test_spider_v2`, `test_heavy`, `test_shadow_step`, `test_grip`, `test_magic`, `test_zero_g`, `test_swim`
- **Dungeons & Systeme:** `test_dungeon_rules`, `test_dungeon_combat`, `test_dungeon_ui`, `test_starhall`, `test_pets`, `test_potions`, `test_fishing`, `test_mine_generator`, `test_root_weave`, `test_star_mirror`, `test_town_rules`, `test_autosave`, `test_cloud_save_coercion`
- **HUD & Menüs:** `test_hud_layout`, `test_hud_profile`, `test_boss_hud_hide`, `test_hotbar_fold`, `test_chat`, `test_mod_menu_v2`, `test_main_menu`, `test_loading_start`, `test_pause_sidebar`
- **Timing-Regel:** Deterministische Frame-Tests mit `--fixed-fps 60`; Echtzeit-Timer-Tests (z. B. `test_magic.tscn`) **ohne** `--fixed-fps`.

### Pixel-Art & Design-Richtlinien
- Vor jeder Art-Arbeit `docs/design_guide.md` und `.agents/skills/shadowspore-pixel-art/SKILL.md` beachten.
- Alle Art-/Audio-Pipelines liegen deterministisch in `tools/art_*.py` und `tools/audio_*.py`. Rohquellen in `tools/art_sources/`, `tools/sfx_raw/`, `assets/ui/sources/` und `docs/` sind per `.gdignore` vom Godot-Import ausgeschlossen.
