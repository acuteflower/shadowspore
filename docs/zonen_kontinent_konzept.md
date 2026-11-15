# Shadowspore — Zonen- & Kontinent-System (Testsystem / Prototyp)

> **STATUS: EXPERIMENTELLES TESTSYSTEM — NICHT OFFIZIELL IM HAUPTSPIEL**
>
> Dieses System ist als **isolierter Prototyp / separates Testsystem** umgesetzt und **nicht** Teil des offiziellen Hauptspiels:
> - Die offizielle Spielwelt bleibt unverändert `WorldLevel` ([world_level.tscn](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/world_level.tscn)) mit den regulären Speicherständen `user://save.json` und `user://coop_save.json`.
> - Im offiziellen Hauptmenü (`MainMenuUi`) gibt es bewusst **keinen** Zonenwelt-Eintrag.
> - Aktivierung und Tests erfolgen ausschließlich gezielt über:
>   1. **Entwicklermenü im Spiel:** `PauseMenu -> ENTWICKLER -> ZONENWELT (TEST)` (`ZONENWELT BETRETEN (NEU)` / `(WEITER)` bzw. `ZURÜCK IN DIE HAUPTWELT`),
>   2. **CLI-Flags:** `godot --path . -- --zones` (neu) bzw. `godot --path . -- --zones-continue` (fortsetzen),
>   3. **Automatisierte Test-/Preview-Szenen:** `tools/test_zones.tscn` und `tools/preview_zones.tscn`.
> - Alle Spielstände des Testsystems liegen streng getrennt unter `user://save_zones.json` (`SaveGame.ZONES_PATH`) bzw. `user://coop_save_zones.json` (`SaveGame.COOP_ZONES_PATH`).

---

## 1. Kernidee: Zonen-Architektur (Lost-Ark-Prinzip)

Anstelle einer zusammenhängenden Open World (`WorldLevel`) unterteilt dieses Testsystem die Welt in **kompakte, organisch begrenzte Einzelzonen**, die über eine **zweistufige Kontinent- & Zonen-Weltkarte** verbunden sind:

- Jede Zone besitzt ein definiertes Thema, organisch geformte Natur-/Waldgrenzen (Klippen/Bäume/Wasser/Void-Rand) und gezielte Ausgänge (`ZonePortal`),
- kombiniert handgesetzte Landmarken, Wege (`ZonePathPatch`) und Story-Orte mit deterministischer prozeduraler Füllung (`ZoneBuilder` + `PropGenerator`),
- wird host-autoritativ in isolierten Welt-Slots (`ZoneInstance` bei `slot_index * 8192 px`) im Speicher aufgebaut, sobald mindestens ein Spieler sie betritt, und sauber entladen, wenn sich kein Spieler mehr darin befindet.

---

## 2. Datenmodell: Kontinent & Provinzen (`data/continents.json` & `ZoneCatalog`)

### 2.1 Hauptkontinent (`"main"` — „GRÜNLAND-KONTINENT“)
- **Biome auf dem Hauptkontinent:** Ausschließlich das Standard-Biom (`meadow`) sowie oben rechts der `witch_forest` (Hexenwald, `witch_forest_poly`). Spätere Biome wie `quartz_desert` liegen **nicht** auf dem Hauptkontinent, sondern auf separaten Übersee-Kontinenten (`unlocked: false`, `via_harbor: "harbor_south"`), erreichbar per Schiffsroute über Küstenhäfen (`harbor_south`, `sunken_shore`).
- **Umgebung:** Ringsum Küste und Ozean (`outer_water: true`) sowie zwei korrumpierte Ränder zur Leere (`void_edges` im Südwesten und Nordosten).
- **Start-/Heimatbereich unten links:** `start_area_bounds: [0.03, 0.79, 0.16, 0.96]` (ca. **13 % Breite × 17 % Höhe** des Kontinents).

### 2.2 Organische Kontinent- & Voronoi-Partitionierung (`ZoneCatalog.continent_layout`)
Um rechteckige/blockige Zonen und ungenutzte Küstenränder zu vermeiden, generiert [zone_catalog.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_catalog.gd) für `"main"` ein deterministisches **`240×150`-Kontinentraster** (`LAYOUT_W × LAYOUT_H`):
- Eine gewichtete Smooth-Min-Insel-SDF formt den organischen Küstenverlauf entlang aller Provinz-Gewichte (`weight`) inkl. Bucht-/Halbinsel-Noise.
- Eine domain-warped Voronoi-Zerlegung ordnet **100 % aller Landzellen** nahtlos den **11 Provinzen** in `data/continents.json` zu (`16177/16177` Landzellen in `test_zones.tscn` geprüft).
- Häfen (`harbors`) werden per `anchor_dir` an die reale Küstenlinie gesnappt; Abfragen laufen über `ZoneCatalog.continent_zone_at_uv(uv)` und `ZoneCatalog.continent_region_of(zone_id)`.

### 2.3 Die 11 definierten Provinzen (Meilenstein 1: 2 spielbar, 9 gesperrt)
- **Entsperrt & spielbar:**
  1. **`start_path` („ALTER ABSTIEG“)** — `104×130` Tiles (`data/zones/start_path.json`): Kanaldeckel-Einstieg (`Manhole`), zerfallene Vorhof-Ruinen (`start_ruins`), Fußwege (`footpath_start`, `footpath_branch`), Schleichpassage mit `guard_spider`, `FallenKnight`, `Signpost` an der Gabelung und offenes Ost-Portal nach `home_valley` (plus gesperrte Nachbarübergänge).
  2. **`home_valley` („VALDRICS TAL“)** — `168×152` Tiles (`data/zones/home_valley.json`): Eigenes Heimat- und Bau-Abteil mit Valdrics `Hut` (`interior_id: "hut"`, `yard_props`, registriert über `Interiors.register_entrance`), offener Baufeld-/Farmfläche (`TownManager`), `WaystoneStatue`, organischem Südost-Weiher (`_ZoneWaterVisual` mit Tiefenfeld, blockiert Baugrund via `town_probe`), offenem West-Rückweg nach `start_path` sowie noch versperrten Portalen zu `north_woods`, `east_meadow` und `harbor_south`.
- **Als Kontinent-Provinzen angelegt (gesperrt / spätere Ausbaustufen):** `harbor_south`, `north_woods`, `east_meadow`, `old_mill_plains`, `sunken_shore`, `hallgrat_plateau`, `witch_border`, `witch_heart`, `spire_hollow` sowie Übersee-Ziel `quartz_desert`.

---

## 3. Organischer Zonenbau & Portale (`ZoneBuilder`, `ZoneInstance`, `ZonePortal`)

- **Organische Zonenform (`ZoneBuilder.compute_zone_shape`):** Jede Zone berechnet über abgerundete Super-Ellipse plus mehrskaligen Rand-Noise (`perimeter.noise_depth: 11` in den Zonen-JSONs) organisch geschwungene Wald- und Lichtungsgrenzen ohne Block-Ecken.
- **Pfade & Wasser:** `ZonePathPatch` zeichnet Erdwege über den Boden-Tiles und meldet `"path"` an `Terrain.patches`; `_ZoneWaterVisual` rendert organisch verzerrte Weiher-Polygone mit Ufer-Flachwasser, schreibend in `ZoneInstance.set_water_depth(...)`.
- **Entladen (`ZoneInstance.unload_from_world`):** Gibt Slot-Tiles auf `Ground`/`Glow`, Props, Decals und `world_things` sauber frei, sobald die Zone leer ist.
- **Portale (`ZonePortal`):**
  - `"walk"`-Portale wechseln beim Durchlaufen (inkl. Ankunfts-Cooldown am Zielportal).
  - `"interact"`-Portale wechseln per `E`, prüfen auf dem Host gegen `unlocked_zones` und lehnen gesperrte Zonen mit Hinweis ab.

---

## 4. Laufzeit, Co-op Option B & Spielregeln (`ZoneWorld`)

[zone_world.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_world.gd) (`extends "res://src/world/test_level.gd"`, Gruppen `"world"`, `"story_world"`, `"zone_world"`) bildet die vollständige Laufzeitumgebung des Testsystems:

- **Co-op Option B (unabhängige Zonen):** 1–4 Spieler können gleichzeitig in unterschiedlichen Zonen spielen. Jede geladene Zone belegt einen eigenen räumlichen Slot `(slot_index * 8192, 0)` (`ZoneCatalog.SLOT_STRIDE_PX`).
- **Host-autoritatives Streaming:** `ensure_zone_loaded(zone_id)` lädt Zielzonen dynamisch; `unload_unused_zones` entlädt unbesetzte Zonen ausschließlich auf Basis des autoritativen `_player_zones[peer_id]`-Mappings (nie anhand noch nicht synchronisierter Client-Koordinaten).
- **Raids (`allow_raids_now()`):** Nacht-Raids greifen nur an, wenn mindestens ein aktiver Spieler in `home_valley` steht.
- **Tod & Respawn (`respawn_point_for` / `on_player_respawned`):** Nach Abschluss des Intros (`opening_over = true`) respawnen besiegte Spieler automatisch zuhause in `home_valley` statt im Startbereich.
- **System-Brücken:** Stellt `coast_tiles()`, `resolve_quest_tile()`, `take_knight()` und `take_torben()` bereit (Settler-Übergang für Valdric ohne `Quarry` läuft dadurch fehlerfrei), und `LeafCritter` prüft `_pending_commit` sicher über `.get("_pending_commit")`.
- **Save-Isolation (`SaveGame`):** `SaveGame.is_zones_world(tree)` erkennt die aktive `zone_world`-Gruppe und leitet automatisch auf `user://save_zones.json` / `user://coop_save_zones.json` (Schlüssel `"zone_world"`) um.

---

## 5. Zweistufige Karte (`ZoneMapView` & `MapWindow`)

[zone_map_view.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/ui/zone_map_view.gd) klinkt sich in [map_window.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/ui/map_window.gd) ein, sobald `zone_world` im SceneTree aktiv ist:

1. **Stufe 1 — Zonen-Karte (`"zone"`):** Zeigt das aus `ZoneBuilder.compute_zone_shape` abgeleitete organische Terrain, Waldrahmen, organische Weiher-Polygone, Wege, Portale (türkis = offen, rot = gesperrt), Wegstein, Valdrics Hütte und Co-op-Diamanten (`P1..P4`).
2. **Stufe 2 — Kontinent-Karte (`"continent"`):** Gecachte `2×`-Kontinent-/Ozean-/Flachwasser-Rastertextur (`_ensure_continent_base_texture`) plus dynamisches Status-Overlay (`_ensure_state_overlay`) für alle 11 Voronoi-Provinzen, Startbereich-Rahmen, Hexenwald-Zone, Leere-Barrieren, eingeschnappte Häfen/Schiffsroute zur Quarzwüste sowie Live-Spielerpositionen. Umschalten per Mausrad, `Tab` oder Header-Button.

---

## 6. Dateien, Test-Einstiege & Verifikation

### Beteiligte Dateien
- **Kern & Welt:** [zone_world.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_world.gd), [zone_world.tscn](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_world.tscn), [zone_catalog.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_catalog.gd), [zone_instance.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_instance.gd), [zone_builder.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_builder.gd), [zone_portal.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_portal.gd), [zone_path_patch.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/zones/zone_path_patch.gd)
- **Daten:** [continents.json](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/data/continents.json), [start_path.json](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/data/zones/start_path.json), [home_valley.json](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/data/zones/home_valley.json)
- **UI & Hooks:** [zone_map_view.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/ui/zone_map_view.gd), [map_window.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/ui/map_window.gd), [game_launcher.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/world/game_launcher.gd), [pause_menu.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/ui/pause_menu.gd), [save_game.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/src/systems/save_game.gd)
- **Tests & Previews:** [test_zones.tscn](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/tools/test_zones.tscn) ([test_zones.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/tools/test_zones.gd)), [preview_zones.tscn](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/tools/preview_zones.tscn) ([preview_zones.gd](file:///c:/Users/levin/OneDrive/Dokumente/GitHub/shadowspore/tools/preview_zones.gd))

### Befehle (Test-Nutzung)
- **Headless Test-Suite:** `Godot --headless --path . --fixed-fps 60 res://tools/test_zones.tscn` (prüft Kontinent-/Voronoi-Partition, organische Zonenränder, dynamisches Slot-Laden/-Entladen, Portale/Sperren, Option-B-Koop, Raids, Post-Intro-Respawn, Save-Isolation und beide Map-Stufen; erwartet `ZONE WORLD TESTS OK`).
- **Visuelle Previews:** `Godot --path . res://tools/preview_zones.tscn -- --dir=/abs/output/dir` (schreibt `zone_start_path.png`, `zone_home_valley.png`, `zone_map_tier1.png`, `zone_map_tier2.png`).
- **Interaktiv starten (nur Test):** `Godot --path . -- --zones` (neu) bzw. `Godot --path . -- --zones-continue` (fortsetzen) oder im Spiel über `PauseMenu -> ENTWICKLER -> ZONENWELT (TEST)`. Hinweis: `--quit` bricht bei `GameLauncher`'s asynchronem `load_threaded_request` bereits im Frame 1 ab — für Headless-Launcher-Checks immer `--quit-after 240` nutzen.
