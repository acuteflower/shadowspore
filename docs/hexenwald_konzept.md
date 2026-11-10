# Hexenwald (Konzept und Stand)

Das erste **neue** Gebiet der Karte: ein eigenes Biom, nicht aus Bestehendem umgewandelt, sondern als neues Land, das die Südküste der Stadtgegend fortsetzt. Thema: ein dunkler, düsterer Märchenwald, in dem Hexen hausen. In Stufe 1 gibt es nur den Boden: Gras in einer dunklen, kühlen Palette, keine Bäume, keine Pflanzen, keine Tiere, keine Orte.

## 1. Leitgedanken

- **Neu, nicht umgebaut.** Alles Bestehende (Küste, Relief, Flüsse, Seen, Regionen 0-30, Storyorte, Stadt) bleibt, wie es war. Geprüft: kein Pixel Altland geht verloren (`relief.png` ändert sich nur dort, wo vorher Leere war), die acht Seen sind byte-gleich, die Flüsse unangetastet. Nur die Küstenabstände direkt am Anschluss ändern sich, weil dort jetzt Land weitergeht.
- **Keine Steg-Anbindung.** Das Land wächst als breite Küstenverlängerung aus der Südküste (rund 60 Tiles Kontaktlinie, der alte Küstenverlauf bleibt als Buchten links und rechts), kein schmaler Hals. Wer südlich der Stadt über die Küstenwiese geht, geht einfach weiter.
- **Nah an der Stadt, aber ein Weg.** Das nächste Hexenwald-Tile liegt 113 Tiles vom Hut (786, 676), die Mitte bei (821, 892), das sind etwa 25 bis 50 Sekunden Sprint.
- **Größer als eine Region, kleiner als eine Überregion.** Rund 38 000 Tiles (etwa 260 x 200 Tiles in der Hüllbox, gelappt), die alten Regionen haben 15 000 bis 25 000, die Überregionen rund 100 000. Platz für Wald, Lichtungen, ein Dorf der Hexen und einen Tümpel.
- **Ein Biom, kein Anstrich.** `witch_forest` hat eine eigene Palette, Dichten, Kartenfarbe und kann später eigene Pflanzen, Tiere und Geräusche bekommen. Eigene Überregion (`super` 5, Region 31, Name "Hexenwald"); Namen bleiben unabhängig vom Biom wie bei den anderen fünf Gebieten.
- **Weicher Übergang.** Der Boden wird nicht an einer Tile-Kante dunkel, sondern über rund 48 Tiles von der Wiesenfarbe in die Hexenwaldfarbe (Weltmaske `g_gloom`, siehe 3). Dieselbe Maske steuert später alles andere, was dunkler werden soll.

## 2. Lage und Form

| | |
|---|---|
| Land | Hüllbox x 684..947, y 788..995, Schwerpunkt (820, 891), 38 158 Tiles |
| Anschluss | Südküste der Region 23/26 (Nebelwald) zwischen x 712 und 868, die Küstenzunge südlich des Altbergwerks (736, 736) |
| Form | Ellipse mit Lappen aus Rauschen (`tools/bake_hexenwald_map.py`, Seed 23), ausgeprägte Landzunge nach Westen, Einkerbungen im Osten |
| Raster | 4x4-Tile-Zellen mit Regions-ID 31; Küste wie überall (glattes Landfeld + Rauschen + Mehrheitsfilter), also dieselbe Küstenoptik wie die alten Gebiete |
| Leere | Außenkante bleibt die Leere (`VoidEdge`). Keine neuen Seen: das neue Land schließt keine Leere ein (geprüft) |
| Gelände | Stufe 2: rund 79 % flach (Level 0), 15 % Hügel (Level 1), 7 % Plateaus (Level 2), dunkle Schieferwände, 33 Rampen/Stufen, ein Weg von der Küstenwiese |

## 3. Technik (was gebaut ist)

### Karte und Küste
- `tools/bake_hexenwald_map.py` setzt Region 31 und Überregion 5 in `data/world_map.json` ein (Zellen, Nachbarn, Tiefe, Fläche, Mittelpunkt, `own_biomes`). Wiederholbar: es entfernt zuerst alles, was Region 31 gehörte. Regionen 0-30 und ihre IDs bleiben. Nach einer Formänderung muss der Fingerabdruck in `editor_compatible_maps` neu gesetzt werden (siehe unten).
- `tools/bake_land_sdf.tscn` backt die Küste neu (jetzt eine Szene, weil `RegionMap` den `DataRegistry`-Autoload braucht; der alte `--script`-Aufruf lief nicht mehr). Dauer unter einer Minute. Geprüft: kein alter Landpixel geht verloren.
- `tools/bake_hexenwald_relief.py` ergänzt `relief.png` nur auf dem **neuen** Land: Stufe 0, Boden, Gras-Stil, Biom-Byte 205 (das sechste Biom). `relief_field.png` und `relief_block.png` brauchen nichts (flacher Boden hat keine Kontur und keine Kollision, vom Skript geprüft).
- `tools/bake_lakes.py` läuft danach neu (Außenkante `outer_sdf.png`, Kartenatlas, Hash). Die acht Seen und alle Flussdaten bleiben unverändert. `rivers_baked.json` wird **nicht** neu gebacken, sein `input_hash` zeigt deshalb auf das alte Relief (er wird nirgends im Spiel geprüft). Das ist beabsichtigt: die bestehenden Flüsse bleiben exakt, das Hexenwald hat noch keinen.
- **Alte Editor-Platzierungen** bleiben gültig: `editor_compatible_maps` kennt jetzt beide früheren Fingerabdrücke und den neuen Layout-Fingerabdruck (`WorldEdits.map_signature()`).

### Biom und Boden
- `data/biomes.json` `witch_forest`: Name, Karten-Farbe `#4d5f72`, `bare` (keine Props), `gloom`/`fade` (Palettenstärke, Übergangslänge in Tiles), `ground` (nur Gras-Kacheln `plain` und `tuft`, 10 %). `data/world_map.json` `own_biomes: ["witch_forest"]` nimmt das Gebiet von der gemeinsamen Wiese aus (`biome` bleibt `meadow`).
- `RegionMap.biome_at/active_biome` kennen eigene Biome. `WorldLevel._land_biome` liefert `witch_forest` (mit dem üblichen Grenzwackeln), `_paint` nimmt für das Biom nur die Kacheln der `ground`-Angabe.
- **Boden-Palette.** Das Gras wird mit denselben Kacheln gezeichnet wie die Wiese, aber `ground_tone.gdshader` liest jede der sechs Grünstufen aus der Hexenwald-Rampe `HEX` statt aus `RAMP`, gemischt nach `gloom`. Dadurch gelten Sonnenflecken, Wolkenschatten, Dunst, Grashalme, Tau, Stadtverschleiß, Nachtgrad und Tageslicht unverändert, nur dunkler und kühler; zusätzlich weniger Sonne, mehr Dunstschatten und stärker violette Schatten. Eine Ränderung durch Rauschen macht den Übergang unregelmäßig.
- **Weltmaske** `BiomeBlend` (`src/world/biome_blend.gd`): aus dem Regionsraster ein 275 x 275 R8-Bild. Wert 0 auf jeder Altland-Zelle (exakt, geprüft), steigend mit der Strecke über Land von der nächsten Nicht-Hexenwald-Zelle (`smoothstep` über `fade` Tiles), Leere-Zellen übernehmen ihre Landnachbarn, damit die Hexenwald-Küste nicht zur Wiese zurückfärbt. Globale Shader-Parameter `g_gloom` / `g_gloom_rect` (`project.godot`), gebaut beim Laden der Welt (~0,15 s). Spätere Stufen lesen `BiomeBlend.amount_at(pos)`.
- **Hinweis zum Stand:** Während dieser Stufe hat eine parallele Arbeit die Pflanzenwelt des Hexenwalds (Stufe 4: `PropGenerator.WITCH_KINDS`, `tools/art_hexenwald.py`, neue Einträge in `plants.json`/`items.json`) auf die Sperre aufgesetzt: `bare` heißt dadurch inzwischen "nur die eigenen Pflanzen des Hexenwalds, nichts von der Wiese". Dieses Dokument beschreibt Stufe 1; die Pflanzenwelt gehört zu Stufe 4.
- **Props-Sperre (Stufe 1).** `PropGenerator.bare` (aus `RegionMap.bare_cells()`) schluckt jeden Kandidaten im Gebiet: keine Bäume, Büsche, Steine, Pilze, Blumen, Stümpfe, Steinbetten. Dazu keine Kleefelder, keine umgestürzten Stämme, keine Glühpflanzen-Kacheln, keine Tiere (die Lebensraumlisten kennen das Biom nicht). Wiesendetails nur als spärliches Gras (`wind.json` `detail_density` 0,3, nur Grasvarianten, dunkel getönt nach `BiomeBlend`).
- **Karte (M).** Eigene dunkle Palette und zwei eigene Symbole (Grasbüschel, Ring); Relief- und Karten-Shader kennen sechs Biome statt fünf. `Relief` behält das Biom-Byte 205 (`_apply_world_biome` überschreibt nur alte Bytes). Entdeckungsnebel, Name, Erkundungsanteil wie bei den anderen Gebieten.
- Wind: `wind.json` `exposure` 0,5 (stehende Luft).

### Gelände (Stufe 2)
- `tools/bake_hexenwald_terrain.py` backt das Relief **nur für die Tiles mit Byte 205**. Die ganze Karte neu zu backen ginge nicht (der Rang des Rauschens über dem Land würde sich verschieben und alle Berge der alten Welt würden wandern), deshalb nutzt das Skript die Funktionen von `tools/bake_relief.py` (Rauschen, Ebenen säubern, Wände, Verbinder, Erreichbarkeit, `export_smooth`) mit `land` = nur Hexenwald. Feld: eigenes Rauschen (Seed 41, Hügel von rund 36 Tiles), Biom-Werte aus `biomes.json` `witch_forest.relief` (gain 1.0, bias -0.1), flach am Außenrand (7..16 Tiles) und entlang des Anschlusses an die alte Küstenwiese (12..28 Tiles, die alte Küste ist dort flach, das Altland wird bewusst nicht angefasst). Die Teile werden über Rampen (70 %) oder Felsstufen (30 %) verbunden, alles ist vom Startpunkt am Anschluss aus erreichbar (Union-Find wie in der Hauptwelt, abgeschnittene Teile werden eingeebnet).
- `relief.png` ändert sich nur auf dem Hexenwald, `relief_field.png`/`relief_block.png` nur in dessen Nähe (3 Tiles Rand), `data/relief.json` behält alle 462 alten Verbinder und erhält die neuen. Geprüft: Altland-Pixel sind identisch mit dem letzten Commit.
- **Stil 5 "Schiefer"** (`relief.gdshader`, `rock()`): kalter, dunkler Fels aus der `STONE`-Rampe (x 0.5/0.58/0.64), sonst wie Fels (Schichten, Moos in den Lagen, Gras-Zungen vom Rand, Waldtreppen). `glows(style)` hält Leuchtadern auf Stil 3/4, `Relief.has_glow_style` entsprechend (Stil 5 leuchtet nicht). Die Wände liegen immer im Stil 5, auch die Böden tragen ihn.
- **Weg** `tools/bake_hexenwald_path.py`: gewichtetes A* auf dem fertigen Relief über flachen Boden (Level 0, Boden, mindestens 4 Tiles Küstenabstand, kein Fluss mit 5 Tiles Rand, Abstand zu Wänden belohnt, langsames Rauschen lässt ihn wandern), von der Küstenwiese etwa 20 Tiles vor dem Anschluss (nächster Punkt zur Stadt, (775, 769)) bis in die Mulde nahe der Mitte (821, 892), 144 Tiles. Schreibt den Eintrag `hexenwald_path` in `data/ground.json` `paths` (eine Zeile, wiederholbar; `"gloom": true`). Das Bild backt `python3 tools/bake_ground.py --path=hexenwald_path` (neu: nur dieser Weg, rund 20 s, mischt sich in `ground_baked.json`); `gloom_tone` dunkelt ihn dort ab, wo der Boden dunkel ist (Python-Gegenstück zu `BiomeBlend`, Glättung über 48 Tiles), damit er nicht gegen den Wald leuchtet. Die vorhandene Prop-Freihaltung entlang aller `paths` gilt automatisch.

### Pflanzendichte (nach Stufe 2)
- Die Hexenwald-Schichten sind dichter (`PropGenerator._witch`): fast jede 22er-Zelle trägt einen Wald (Schwelle 0,86 + 0,3 wild statt 0,68), Einzelbäume 60 %, Streublumen (Zelle 4, 85 %) und Gruppen/Ringe (Zelle 10, 75 %), im Unterholz mehr und breitere Mischung. Gemessen in den Chunks um das Gebiet: 1085 Pflanzen vorher, jetzt rund 1770 eigene plus rund 730 Büsche.
- **Wiesenbüsche** (`bush`, "Lichtungsbusch", nicht pflückbar) wachsen jetzt auch im Hexenwald (`PropGenerator.WITCH_SHARED`, Erlaubnis in `_add`): aus den Wiesenschichten (Einzelbüsche, Dickichte, Hainunterholz) und als Teil der Hexenwald-Schichten. Beeren- und Glutbüsche bleiben draußen. Sie werden dort von `BiomeBlend` abgedunkelt (`WorldProp._setup_gloom`, `GLOOM_TINT`), damit sie nicht limettengrün gegen den Boden leuchten (die Tönung aller Props bleibt Stufe 3).

### Dauerdämmer (Stufe 3, erster Teil)
- `DayNight._update` liest `BiomeBlend.amount_at` in der Bildmitte der Kamera (`_gloom_here`, nur draußen) und mischt die Tagesfarbe mit `GLOOM_DAY` (0,56 / 0,62 / 0,74), nachts mit dem milderen `GLOOM_NIGHT`, die Nacht bleibt also die dunkelste Zeit. Sonne (Flecken, Schächte) fällt um 90 %, Goldene Stunde ganz aus. Leuchtpflanzen, Mondflecken und Dunst laufen mit mindestens 0,45 Nachtstärke (`GLOOM_GLOW`), auch mittags. Der Übergang ist so weich wie die Boden-Maske (48 Tiles). Alles kosmetisch, lokal je Spieler; die echte Tageszeit (Gegner, Tiere, Nachtsystem) ist unverändert. Offen aus Stufe 3: Bodennebel, eigenes Geräuschbett, Tönung weiterer Props.

### Der Hexenturm am Wegende
- Der Turm selbst (Art `tools/art_witch_tower.py`, Node `WitchTower`) war schon fertig und wurde nur noch eingebaut: `data/ground.json` `towers` (`hexenwald_tower`, Tile (830, 892) = Fuß des Tors), von `WorldLevel._add_ground_decals` gesetzt, 9 Tiles um Körper und Hof frei von erzeugten Pflanzen.
- `tools/bake_hexenwald_path.py` sucht den Standort selbst: nächstes Rechteck von 17 x 10 Tiles aus lauter flachem, freiem Boden zur Mitte des Gebiets (Körper hinter dem Tor, Hof davor). Der Weg ist jetzt auf das Tor ausgerichtet (Ziel 3 Tiles südlich des Fußes, der Turmkörper ist für das A* gesperrt, der Weg läuft also um ihn herum bis vors Tor; `taper_out` 24). Nach Änderungen: `bake_hexenwald_path.py`, `bake_ground.py --path=hexenwald_path`. Der Innenraum, die Hexe und der gebannte Ring folgen später (`docs/hexenwald_nebel_konzept.md` Abschnitt 8).

### Tiere (2026-11-10)
- Krähen und Raben leben im Hexenwald, häufiger und in größeren Schwärmen als auf der Wiese (`wildlife.json` Block `witch_forest`, `CorvidPopulation.local_spec`). Befund zur Pflanzenwelt, weitere Tiere und Reihenfolge: `docs/hexenwald_leben_konzept.md`.

### Nicht gebaut (Absicht)
Bäume (siehe Hinweis oben), Pflanzen, Tiere, Gewässer, Orte, Quests, Geräusche, Nebel-Stimmung, Gegnerauswahl, Waystone, Dialoge.

## 4. Palette

Die Wiese (`RAMP` in `tools/art_grass.py` und `ground_tone.gdshader`) ist warm und kräftig. Der Hexenwald ist dieselbe Welt bei kaltem, schwerem Licht: Blaugrün mit Violett, wenig Sättigung, enger Kontrast, Licht nur als blasse Flecken.

| Stufe | Wiese | Hexenwald |
|---|---|---|
| 0 | `#22483c` | `#0d0f1a` |
| 1 | `#2f6250` | `#131e26` |
| 2 | `#3e7d56` | `#1b2c2d` |
| 3 | `#559860` | `#273d38` |
| 4 | `#7cb96d` | `#38503f` |
| 5 | `#a8dc8c` | `#506848` |

Karten-Farbe `#4d5f72` (kühles Violett-Grau), damit sie sich von Glasklippen (`#8a6fd6`) und Leerenblühen (`#c9506f`) unterscheidet. Die Werte stehen in `HEX` im Shader und sind zum Nachziehen gedacht.

## 5. Stufen (Plan)

1. **Gebiet und Boden** (gebaut): Land, Karte, flacher dunkler Grasboden, weicher Übergang, keine Props, Tests.
2. **Gelände** (gebaut): Hügel, Plateaus, Schieferwände (Stil 5), Verbinder, ein Weg von der Küstenwiese hinein. Offen: Lichtungen per `bake_ground`, ein Tümpel, Treppenstile.
3. **Stimmung:** Dauerdämmer (Tageslicht gedämpft über `g_gloom`), niedriger Bodennebel (`NightAtmosphere`), eigenes Geräuschbett, kalte Mondflecken, eigene Lichtfarbe der Leuchtpflanzen, Tönung von Props nach `BiomeBlend.amount_at`.
4. **Bäume und Pflanzen:** verdrehte Hexenbäume (neue Baumart wie Weide/Blüte, `art_tree2.py`), Dornenhecken, Pilzringe, Giftblumen, Moos, Farne, Nachtblüher; Waldboden-Betten; ein Tümpel (Wasser nur dort backen). `bare` wird dann pro Gruppe gelockert.
5. **Tiere und Nacht:** Raben, Eulen, Kröten, Irrlichter, ein eigenes Nachtwesen; `night.json` `species`, Gegnerwerte nach Stadtstufe.
6. **Orte:** Hexenhütte mit Innenraum (`Interiors`), Kesselplatz (verknüpft mit *Lies den Kessel*), Steinkreis, Waystone, Wegweiser an der Küstenwiese.
7. **Geschichte und Figuren:** Hexen, Questkette, Dialoge (Figuren und Texte kommen von den dafür vorgesehenen Agenten).

Jede Stufe darf das Gebiet vergrößern, nicht verändern: Land, IDs und Region 31 bleiben.

## 6. Befehle und Prüfungen

Neu backen (nur nach bewusster Änderung der Form in `bake_hexenwald_map.py`; `HEX_SEED=n` probiert andere Formen):

```
python3 tools/bake_hexenwald_map.py [vorschau.png]
Godot --headless --path . tools/bake_land_sdf.tscn
python3 tools/bake_hexenwald_relief.py
python3 tools/bake_lakes.py
Godot --headless --path . --import
```

Gelände und Weg (Stufe 2, nach `bake_hexenwald_relief.py`, jeweils wiederholbar):

```
python3 tools/bake_hexenwald_terrain.py [vorschau.png]
python3 tools/bake_hexenwald_path.py [vorschau.png]
python3 tools/bake_ground.py --path=hexenwald_path
python3 tools/bake_lakes.py
Godot --headless --path . --import
```

Danach den Layout-Fingerabdruck in `data/world_map.json` `editor_compatible_maps` nachziehen (`WorldEdits.map_signature()` ausgeben, alle `layout`-Einträge ersetzen).

Prüfungen: `python3 tools/test_hexenwald_terrain.py` (Altland gleich HEAD, Anteile, Wände, Erreichbarkeit, Verbinder, Kollision, Weg), `python3 tools/test_hexenwald_bake.py` (Karte, Küste, Relief, Seen, Abstand), `tools/test_hexenwald.tscn` (Biom, Weltmaske, Props-Sperre, Boden, Karte), angepasst `tools/test_shared_biome.tscn`, dazu die Regressionen `test_forest`, `test_lakes`, `test_streaming_performance`, `test_lakes_bake.py`, `test_rivers_bake.py`, `test_map_water.py`.

Vorschau: `Godot --rendering-driver opengl3 --path . tools/preview_daylight.tscn -- --dir=/abs/ordner --times=0.5,0.8 --at=826,860 --phase=12` zeigt das Gebiet bei Tag und Dämmerung (`--at=826,812` die Küstenwiese mit dem Übergang, `--zoom=0.5` mehr Überblick). Hinkommen im Spiel: ENTWICKLER, TELEPORT, Koordinaten `820, 880`.
