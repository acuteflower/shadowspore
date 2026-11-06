# Leben an Flüssen und Seen

## 1. Wasserpflanzen (`RiverDetails._water_flora`, Zeilen 20-22)
Art `tools/art_water_plants.py` → `assets/water/water_flora{,_glow}.png` (32x32, 6 Varianten x 6 Zeilen). Pro Chunk höchstens `water_flora_max` (18, je ein Drittel pro Art), in Klumpen aus 2-4, nur im Wasser (>= 4 px vom Ufer, Seen bevorzugt), deterministisch je Chunk.
- **Linsenteppich**: Matte aus winzigen Blättern auf ruhigem Flachwasser, driftet mit der Strömung, zwei Schimmerframes, leuchtendes Plankton.
- **Goldmummel**: schwimmende Herzblätter mit goldenen Kelchblüten; tagsüber offen, nachts geschlossene, glimmende Knospen.
- **Federkraut**: durchscheinendes Hornkraut unter der Oberfläche in tieferem Wasser, wiegt sich in der Strömung, leuchtende Spitzen, aufsteigende Bläschen.
Mondiris/Mummel/Federkraut haben wie die Landpflanzen eine Tintenkontur, der Linsenteppich (Einzelpixel) nicht.

## 2. Uferpflanzen (`Flora`, `tools/art_shore_plants.py`)
**Mondiris** (Irisblüte, Bart aus Licht), **Bachminze** (Tee: heilt 3 + 8/6 s), **Sumpfdotter** (goldene Kelchblüten). Erzeugung: Ebene `water_edge` (Zellen 4 Kacheln) wählt nach Abstand zur Wasserkante (`PropGenerator.water_dist` = `WorldRivers.field_at().x`): Sumpfdotter direkt am Wasser, Iris dahinter, Minze weiter weg bis ~7 Kacheln. Sie dürfen bis 4 px an das Ufer (`SHORE_KINDS`, wie Rohrkolben), alles andere hält den normalen Abstand. Außerdem steigen in `_flora_kind` Rohrkolben, Nebellilie, Mondglöckchen und Leuchtfarn mit der Wassernähe (`_near_water`), Wispersaat/Mohn fallen.

## 3. Tiere (`RiverAnimal`, Daten `data/river_animals.json`, Kunst `tools/art_water_animals.py`)
Gleiches Netzwerkmodell wie die vorhandenen Flusstiere: der Host entscheidet, atomare `_act`-Pakete (jetzt mit `aux`) laufen auf allen Peers, Spätbeitritt per Snapshot; Ellipsoid-Pixelrenderer, acht echte Richtungen, Sheets `assets/wildlife/{heron,frog,kingfisher,duck}.png`, Rufe `tools/audio_water_animals.py`.
- **Reiher** (64x64, 2 Fellfarben): steht, hockt, putzt sich, watet langsam im Flachwasser, jagt (Hals schießt vor, die Fische in der Nähe stieben auseinander, `RiverFauna.scare_fish`, mit Glück Fisch im Schnabel) und fliegt mit Start/Landung weg, wenn man zu nah kommt.
- **Frosch** (ersetzt die alte Zeichnung, 2 Farben): sitzt am Ufer, quakt mit aufgeblasener Kehle (nachts oft), hüpft, schwimmt, taucht ab.
- **Eisvogel**: sitzt auf einem Schilfhalm, dreht den Kopf, stürzt sich auf Fische (Spritzer und Ringe), kehrt mit Beute zurück und hält sie kurz im Schnabel, fliegt bei Gefahr zum nächsten Halm.
- **Ente**: Erpelpaare (fliegen bei Gefahr davon) und Entenfamilien (Henne mit 3 Küken in einer Reihe, flüchten paddelnd); schwimmt mit Kielwasser, gründelt mit hochgestrecktem Hinterteil, putzt sich.
Auch Frosch/Ente/Reiher rufen leise mit Abstandsdämpfung (`AudioStreamPlayer2D`, Abklingzeit 14-30 s).

## Prüfungen
`tools/test_river_life.tscn`, `test_river_animals.tscn` (alle 8 Arten, Sheetmaße, gültige Routen und Flüge), `test_world_rivers.tscn`, `test_flora.tscn`, `test_streaming_performance.tscn`. Vorschau: `tools/preview_world_rivers.tscn -- --lake=N --capture=...`, Tierbogen `docs/img/water_animals.png`.

## Revision: heron, ducks, one family of water plants
- Heron redone (`tools/art_water_animals.py`): tilted torso with shaggy breast plumes, silvery scapulars, black shoulder patch, flight feathers crossing over the tail, dotted throat streak, white crown with two crest plumes, ochre legs with feathered thighs. **Flight**: arm in three segments (shoulder/wrist/hand lagging each other), covert, secondary and fingered primary feathers, the neck drawn into a thick S, legs trailing; takeoff pitches nose up with the legs swinging back, landing swings them forward and down. Same frame layout as before.
- Ducks: drake (grey back, green head, white collar, chestnut breast, black curled stern, yellow bill), hen (mottled browns, dark eye stripe, orange bill with dark saddle), duckling (yellow, dark back stripe, pale face). Blue speculum with white bars shows on folded and flying wings.
- Water plants share one language: the `GREEN` ramp of the land flora, ink outline for everything standing or floating above the surface (sedges, pads, mummel, rocks), no outline for what lives under it (grasses, hornwort, gravel, duckweed film), a dark contact shadow and teal ripple at every foot. `python3 tools/art_river_details.py` and `python3 tools/art_water_plants.py`, then `--import`.
- Clover fields: 2-4 attempts per chunk (was 0-2), 5 spots per field, looser open-ground test, and fields keep a distance from each other.
