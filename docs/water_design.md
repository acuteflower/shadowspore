# Gewässer – Designstand, Schritt 1

Schritt 1 liefert echte Pixel-Assets, einen animierten Wasser-Renderer und eine isolierte Designszene. Die Weltkarte, Kollision, Spielerbewegung und Tierwelt werden hier noch nicht verändert. Schritt 2 übernimmt Gewässernetz, Streaming, Übergänge und Begehbarkeit; Schritt 3 die Tierwelt und gemeinsame Abstimmung.

## Bildsprache

Gedecktes Petrol mit kühlgrünen seichten Bereichen und dunkler Mitte. Kies bleibt im flachen Wasser am Boden; kleine Reflexgruppen folgen der lokalen Strömungsrichtung. Unregelmäßiger dunkler Nasssaum, kurze erdige Uferabschnitte und Grasübergang. Helligkeit bleibt im Tages-/Nachtlicht der Welt, ohne Eigenleuchten. Wasserfälle: moosige Felskante, aufgebrochene fallende Bänder und gedämpft heller Schaum.

Die Testkomposition zeigt einen schmaleren Zufluss, breiteren Bach, Zusammenfluss, Kiesfurt und 32px-Wasserfall neben bestehender Vegetation/Felsen und der Spielerin als Maßstab. Die Furt wird quer zur Strömung flach, ohne kreisförmigen Fleck. Weich interpolierte Pfade und kleine ortsfeste Uferabweichungen verhindern rechtwinklige Kanäle. Für die endgültigen Weltrouten kommen in Schritt 2 Gelände-/Gefälleprüfungen hinzu; diese Szene ist ein visuelles Muster, kein hydrologischer Generator.

## Assets und Schnittstellen

- `tools/art_water.py` reproduziert `assets/water/water_detail.png` (Datenkanäle für ortsfesten Grund und bewegte Reflexe), `bank_material.png`, `waterfall.png` (8 Frames à48×48, 10fps), `waterfall_rock.png` (48×48), `shore_details.png` (4×32×32: Schilf, Wurzeln, Kiesbank, Wasserstein; Fußpunkt16,28).
- `assets/shaders/river_water.gdshader`: `TEXTURE` R=Wasserfläche, G=Tiefe0..1, BA=Fließrichtung von[-1,1] nach[0,1]. `bank_map` R=Abstand/`bank_width`. Masken sind Daten, keine kolorierten Kunst-Assets. Detailtexturen wiederholen sich mit Nearest-Filter.
- `world_origin` verankert Materialdetails im Raum, `water_time` steuert die Animation explizit. Pause friert Wasser und Wasserfall ein. Kein unabhängiges Shader-TIME für Wasser.
- `RiverDesignPatch` berechnet ein deterministisches gemeinsames Feld aus Pfaden mit variablen Radien. Fließrichtung, Tiefe und Uferabstand stammen aus derselben Geometrie. Es meldet sich ausdrücklich noch nicht bei `Terrain` an.
- `data/water_design.json` hält die Testkomposition und Animationswerte. Spätere Chunk-Masken müssen in Weltkoordinaten und mit Nachbarschaftsrand abgetastet werden, um Nähte zu vermeiden. Die komplette Vorschau-Maske ist kein Laufzeit-Bake für jeden Weltchunk.

## Vorschau und Tests

`Godot --path . tools/preview_water.tscn` öffnet Tag/Nacht und Animationspause. Ohne Savezugriffe oder Multiplayer-Port. Aufnahme: `-- --capture=/absolute/day.png --animate=/absolute/frame_folder`; Nacht: `-- --night --capture=/absolute/night.png`.

`Godot --headless --path . tools/test_water_design.tscn` prüft Geometrie, Tiefe/Furt, Fließrichtung, reproduzierbare Masken, Pausieren und Asset-/Frameverträge. Native Aufnahmen prüfen die Shader tatsächlich im Renderer; `python3 tools/check_water_capture.py FRAME_FOLDER DAY.png NIGHT.png` kontrolliert Wasserbewegung, feste Ufer und Nachttönung.

Art und Shadergestaltung: GPT-6.1-Terra-Subagent gemäß Nutzerwunsch. Renderer-Anbindung, Geometrie, Tests und Dokumentation: Hauptagent.

## Prüfergebnis

33 technische Prüfungen bestanden. Native Renderprüfung über40 Frames: Wasser bewegt sich, trockene Ufer bleiben bildstabil, Wasser wird bei Nacht abgedunkelt (mittlere Helligkeit44% der Tagansicht). Tag-/Nachtaufnahmen visuell geprüft. Aufnahmen: `docs/img/water_design{_day.png,_night.png,.gif}`.

## Überarbeitung nach Designfeedback

Die zunächst zu glatte Oberfläche wurde durch ineinandergreifende, gestufte Farbflächen und breitere gebrochene Reflexgruppen ersetzt. Gedecktes Türkis/Petrol und helle Schaumtöne verbinden Bach und Wasserfall. Ruhigere tiefe Partien bleiben zwischen bewegten Reflexen erhalten. Untergetauchter Kies wird langsam um einen Pixel gebrochen; kein weichgezeichneter Vollbildfilter.

`disturbances[8]` im Shader hält Weltposition, Radius und Stärke örtlicher Störungen. `RiverDesignPatch.set_disturbances` wandelt lokale Anker in Weltkoordinaten um und begrenzt auf acht Quellen. Im Muster liegen sie am Wasserfall-Aufprall und zwei Steinen. Gebrochene elliptische Wellen und kurze auslaufende Schaumspuren bleiben auf Wasser begrenzt. Alles nutzt denselben pausierbaren Zeitwert.

Aktualisierte native Prüfung:40 Frames, feste Ufer, korrekte Nachtabdunklung. Vergleich bei identischem Animationszeitpunkt mit/ohne Störungen:1.652 Wasserpixel betroffen, ausschließlich im Umfeld der Anker. `check_water_capture.py` akzeptiert dafür als viertes Bildargument die Aufnahme mit `--no-disturbances`. Neue Ansichten unter `docs/img/water_design_harmony{.gif,_day.png,_night.png}`; die frühere Ansicht bleibt zum Vergleich erhalten.

## Verbundener Wasserfall

Zulauf und Empfangsbecken überlappen das Fall-Sprite. Ein durchgehender Wasserfußabdruck unter der fallenden Fläche verhindert trockene Uferstreifen zwischen den Abschnitten. Die Felskanten liegen seitlich darüber. `waterfall_height`/`waterfall_width` stehen in der Designdatei; `waterfall_links[4]` (Welt-X/Y der Lippe, Höhe, Breite) und `fall_link_count` verbinden Oberfläche und Fall im Shader. Oben ziehen Rinnsale über die Kante, unten lösen sich die unregelmäßigen Schaumflecken über25px in der Empfangsströmung auf. Der Sprite bleibt48×48/8Frames; seine Wasserbänder beginnen bei y0 statt erst bei y5.

33 technische Checks einschließlich durchgehend nassem Anschluss, korrekten Weltkoordinaten und gemeinsamem Animationstakt bestanden. Native40-Frame-/Nachtprüfung bestanden: feste Ufer, Wasser bei44% Tageshelligkeit; örtliche Störungen auf1.708 Wasserpixel begrenzt. Ansichten `docs/img/water_design_connected{.gif,_day.png,_night.png}` und Nahaufnahme `waterfall_connected_closeup.gif`.
