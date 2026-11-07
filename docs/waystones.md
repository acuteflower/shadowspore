# Wegsteine (Teleportationspunkte)

Göttliche Jungfrauen-Statuen aus hellem Violettstein, mittelmäßig beschädigt und überwuchert, mit **dunklen Kristallen**, die aus ihnen wachsen. Später verteilt über alle Regionen der Welt und Teleportziele. **Gebaut ist bisher:** die erste Statue, das Aktivieren (Animation, Karte, Speicherstand, Mehrspieler). **Auch gebaut:** Reisen zwischen erwachten Statuen (siehe unten), zwei Statuen. **Noch nicht gebaut:** Kosten/Abklingzeit des Reisens, weitere Statuen, Klänge von echter Hand, Dialogtexte.

## Die erste Statue
`data/waystones.json` → `hang_wachterin` ("WÄCHTERIN AM HANG", Name ist Platzhalter), Kachel **(840, 649)**: die Mitte der runden Erhöhung (Ebene 3) nahe der Stadt, Aufstieg über die Rampe an ihrer Südseite. 5 Kacheln rundum bleiben frei von generierten Props.

## Erster Fund
Kommt Ellie zum ersten Mal einer Statue näher als 150 px (beliebige, auch eine erwachte), spricht sie einmal ein **kleines Gespräch** (`data/dialogue.json` `waystone_discover`, 3 Zeilen, Platzhaltertexte für den Dialog-Autor; Flag `waystone_seen` im Quest-Stand, `WaystoneStatue._check_discovery`).

## Ablauf der Aktivierung
1. Nähert sich Ellie, steht über der Statue **E AKTIVIEREN** (nur solange sie schläft).
2. E → Ellie spielt die **Berührungs-Animation** (`Player.begin_touch`, `player_touch.png`: beide Hände heben sich, die Handflächen legen sich bei 0,45 s auf den Stein und bleiben dort, bis die Statue aufblüht, dann zuckt sie zurück: `Player.release_touch`) → dort ruft die Statue `Waystones.request_activate` → Host prüft Reichweite (46 px + Toleranz), lebende Spielerin, noch nicht wach → markiert sie wach und sagt allen `_rpc_awakened`.
3. **Alle Peers** spielen `WaystoneStatue.awaken()` (≈ 6 s): 1,3 s Flackern (die dunklen Kristalle regen sich), dann läuft das Licht **von den Kristallen über den Stein** (3,5 s, pro Pixel steht in `statue_wave.png`, wann es ihn erreicht): Risse heilen, Bewuchs (Moos, Efeu, Wurzeln, Pilze) welkt **vor** der Lichtfront, abgebrochene Hand und Plinthenkante sind wieder ganz, Kristalle leuchten auf, Runen und Augen glühen. Die Lichtfront ist eine gedithert leuchtende Linie. Dazu Laub-/Gesteinsstaub, steigende Lichtfunken, Ringe aus Licht am Boden, die **Lichtsäule** (`waystone_beam.gdshader`, Bayer-gedithert), bei 4,8 s **Aufblühen** (Blitz, `ShockRing`, Kamerabeben), danach ruhiges Pulsieren, Bodenlicht (`NightLight`), leiser Summton.
4. **Nur bei der Spielerin, die E gedrückt hat:** `WaystoneScene` hält sie still, zoomt die Kamera heran (x1,9) auf die Statue, Ellie spricht eine Zeile (Platzhalter), dann **öffnet sich die Karte von selbst** an der Statue (`MapWindow.present`), der Nebel hebt sich in einem Radius von 15 Karten-Zellen (60 Kacheln; Host: `MapDiscovery.reveal_disc` nach `reveal_delay` 6,3 s), ein Ring aus Licht läuft aus dem Wegstein-Zeichen; nach 4,6 s (oder M/Esc) schließt sie sich, Banner "WEGSTEIN ERWACHT", Kamera zurück, Spielerin frei.
5. Auf der Karte (M) stehen erwachte Wegsteine als türkisfarbener Kristall mit Namen.

## Technik
- `WaystoneStatue` (src/entities/props, `Interactable`): Körper = `waystone_awaken.gdshader` (verwildertes Blatt + gereinigtes Blatt + Wellenkarte, `progress`), Leuchtschicht = `waystone_glow.gdshader` (ungetönt: schwache Glut vor dem Erwachen, danach Kristalle/Runen/Augen/Halo, Lichtfront, Blitz). Körper bleibt weltbeleuchtet.
- `Waystones` (src/systems, Gruppe `waystones`, Knoten `Waystones` des `WorldLevel`): Zustand `awake`, Host-validiert, Snapshot an Beitretende, Speicherstand `"waystones"` (`export_state`/`import_state`). `entries()` liefert die Tabelle für Karte und später ein Reisemenü.
- Eintrag in `data/waystones.json`: `id`, `name`, `tile`, `reveal` (Zellen), `clear_radius`. Neue Statue = neuer Eintrag.
- Karte: `MapWindow.present(tile, sekunden, ring_kacheln)`, `_draw_waystones`.

## Art (`py -3 tools/art_waystone.py [vorschau.png]`)
Gleicher Ellipsoid-Renderer wie Heldin/Wegweiser/Bäume, mit einem eigenen Rasterizer in `art_waystone.py` (`raster`) für die **facettierten Kristalle** (Kind `facet`: die Normalen der Ellipsoid-Kette rasten auf sechs ebene Flächen ein). Die Statue ist ca. 1,6 x so hoch wie Ellie (`h.SCALE` 0,74), hat ein großes freies Gesicht (geschlossene Augen unter Brauen; erwacht leuchten die Augen türkis), einen goldenen **Heiligenschein** mit einem Strahlenkranz aus Kristallen dahinter, Schleier, Zöpfe, Schärpe vom erhobenen Arm, goldene Reife. Der Halo der Leuchtschicht liegt nie über der Statue selbst, damit er das Gesicht nicht verdeckt. Schreibt `assets/props/waystone/`: `statue_wild.png` (gefunden: Risse, abgebrochene linke Hand, Moos/Efeu/Wurzeln, dunkle Kristalle), `statue_clean.png` (erwacht: ganz, poliertes Gold, leuchtende Kristalle), `statue_glow.png` (nur Leuchtpixel + gedithertes Halo), `statue_dim.png` (schwache Glut des schlafenden Steins), `statue_wave.png` (R = Zeitpunkt, A = Körpermaske) und `data/waystone_art.json` (Pixelpositionen von Kristallen, Runen, Herz-/Handkristall). Frames 104x112, Füße bei Zeile 92. Wer das Modell ändert, lässt das Skript laufen und danach `Godot --headless --import`.
Klänge: `py -3 tools/audio_waystone.py` → `assets/audio/waystone/` (swell, crumble, chime_a-c, bloom, hum; synthetische Platzhalter).

## Test
`Godot --headless --path . --fixed-fps 60 tools/test_waystones.tscn` (Echtzeit ≈ 20 s; Statue, Aktivierung, Nebel, Szene, Speicherstand). Mit Fenster: `--rendering-driver opengl3 ... -- --capture=/abs/ordner` speichert ein Bild je Moment.

Berührungs-Animation: `py -3 tools/art_hero3d.py touchonly` (≈ 30 s; schreibt `assets/characters/player_touch.png`, `player_touch_blood.png` und die `touch_*`-Einträge in `data/hero_rig.json`; Keyframes `TOUCH_KEYS`). Im Spiel `Player` Sheet 5.

## Reisen (zweite Statue und Karte)
- Zweite Statue: `ebene_wachterin` ("WÄCHTERIN DER EBENE", Platzhaltername) bei Kachel (598, 523), flaches Land der Ebene 0, steht dort auf einer Landzunge am Wasser.
- E an einer **erwachten** Statue ("E REISEN"): `Waystones.begin_travel` → `WaystoneTravel` (Kind der Spielerin): Ellie **geht näher** (`Player.auto_walk`, `auto_walk_factor` 0,5), legt wie beim Erwecken **beide Hände auf die Statue**, die Statue flackert auf, die Karte öffnet sich im **Reisemodus** (`MapWindow.open_travel`).
- Karte im Reisemodus (`MapWaystones`, src/ui/map_waystones.gd): alle erwachten Statuen sind **hervorgehoben** (doppelt so groß, pulsierende Ringe), die eigene heißt "HIER" (Gold). Maus darüber (oder A/D bzw. Pfeiltasten) wählt: gestrichelte Route von hier, Karte mit Name und Entfernung. **Halten** (linke Maustaste auf dem Marker oder E) schließt einen Lichtring in ca. 1,15 s und reist. Esc/M bricht ab, dann tritt Ellie zurück.
- Reise: Statue flammt, Licht flutet den Bildschirm, `Player.request_teleport` vor die Ziel-Statue (28 px südlich), nach kurzer Ladezeit blendet das Licht ab, die Ziel-Statue flammt auf (`WaystoneStatue.flare`).
- Der Marker (Haloring mit Strahlenkranz über Kristall auf Plinth, atmet türkis) steht auch auf der normalen Karte (M) mit Namen; Teleportieren geht nur im Reisemodus, also nur an einer Statue.

## Verteilung über die Welt (8 Statuen)
Nicht jede Gegend bekommt gleich viele, jede der fünf Gegenden mindestens eine, die Abstände sind 110+ Kacheln. Die Standorte sind **Plateaus der Ebene 2-3** (Aussichtspunkte) mit einer ebenen Fläche von mindestens 7 Kacheln Radius, 8+ Kacheln vom Wasser und 15+ von der Küste, jeweils mit dem Stil der Gegend (Auswahl per Skript aus `relief.png`, `land_sdf.png`, `map_water.png`; Vorschau jeder Stelle: `tools/preview_waystones.tscn`).

| Gegend | Statue | Kachel | Ebene |
|---|---|---|---|
| Nebelwald | WÄCHTERIN AM HANG (bei der Stadt) | 840, 649 | 3 |
| Nebelwald | WÄCHTERIN DER EBENE (Seeufer) | 598, 523 | 0 |
| Die Lichtung | WÄCHTERIN DER LICHTUNG | 373, 858 | 2 |
| Glasklippen | WÄCHTERIN DER KLIPPEN | 215, 660 | 3 |
| Glasklippen | WÄCHTERIN DES GLASKAMMS | 142, 355 | 3 |
| Das Leerenblühen | WÄCHTERIN DER BLÜTE (Weg zur Boss-Arena) | 408, 322 | 3 |
| Versunkene Ruinen | WÄCHTERIN DER ALTEN MAUERN | 664, 390 | 3 |
| Versunkene Ruinen | WÄCHTERIN DER VERSUNKENEN | 915, 308 | 3 |

Alle Namen sind Platzhalter. Eine neue Statue = ein Eintrag in `data/waystones.json`.

## Steinboden und Bodenkristalle
- Jede Statue steht auf einem **handgelegten Steinfeld** (200x120 px, Bodenebene z -9), in den Farben des Statuenmarmors (eine Stufe dunkler): um den Sockel ein **Ring sauber gesetzter Platten**, nach außen immer kleinere, unregelmäßige **Pflastersteine** und Kies, jede Platte mit eigenem Ton (kühl/neutral/warm), heller Kante oben links, dunkler Fuge unten rechts, Absplitterungen, ausgefranster gedietherter Rand. Schlafend ist es **leicht bewachsen** (Moos in den Fugen, ein paar Grasbüschel, winzige helle Blüten, wenige Haarrisse); beim Erwachen läuft die Welle **vom Sockel nach außen** (gleicher Shader und `progress` wie die Statue): poliert, Bewuchs weg, dafür **leuchten türkisfarbene Leylines** (vom Runenring zu den Kristall-Sockeln), ein **Runenring**, Licht in den Spalten und violette Kristallsplitter. Unter den Füßen ist es `stone` (`WaystoneStatue.surface_at` über `Terrain.patches`).
- **Zwölf Kristall-Sockel** sind Teil des Bildes (Spalte mit Schatten, davon ausgehende Risse, angehobene Bruchstücke, Splitter). Pro Statue stehen **5 bis 7 kleine dunkle Kristallgruppen** auf einer anderen Auswahl davon (aus der Statue-ID gewürfelt, nie vor dem Sockel; zehn sehr verschiedene Formen, jede höchstens zweimal, 5 bis 20 px hoch). Jede leuchtet auf, wenn die Welle ihre Entfernung erreicht, und glüht danach mit der Statue (flackert vorher leise). Die Kristalle sind Geschwister-Knoten der Statue, damit sie wie normale Props sortieren.
- Art: `py -3 tools/art_waystone_ground.py [vorschau.png]` (reines numpy, 2D): `ground_wild/clean/glow/dim/wave.png`, `crystals_wild/lit.png`, `data/waystone_ground.json` (Größen, Sockelpositionen); danach `Godot --headless --import`. Ansicht aller Standorte schlafend/erwacht: `tools/preview_waystones.tscn -- --capture=/abs/ordner [--awake]`.
