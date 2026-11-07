# Umgefallene Baumstämme und Tierbegegnungen

## Echte Stammtexturen

`tools/art_fallen_logs.py` verwendet denselben Ellipsoid-/Pixelrenderer wie die stehenden Bäume, der Ritter am Stamm und die Hütte. Es erzeugt drei Modelle mit jeweils acht separat gerenderten Ansichten. Es gibt keine Laufzeitrotation oder geglättete Streckung der Bilder.

- `assets/props/fallen_logs.png`: 896 × 240 Pixel, acht Spalten und drei Zeilen mit 112 × 80 Pixeln je Ansicht.
- `assets/props/fallen_logs_glow.png`: deckungsgleiche kleine Pilz-/Aderlichtflächen.
- `data/fallen_logs.json`: Fußanker und Bodenendpunkte jeder Ansicht sowie Streuungswerte.

Rinden- und Holzfarben entsprechen dem vorhandenen gefallenen Stamm und der Hütte: Pflaumenbraun, dunkle Rindenspalten, helle Jahresringe an gebrochenen Enden, kühles Moos, sparsame violette Adern und kleine türkisfarbene Baumpilze. Varianten: längerer verwurzelter Stamm, kurzer abgebrochener Abschnitt und dunklerer, stärker bemooster alter Stamm.

Texturrevision: Die regelmäßigen Querrillen wurden durch überlappende längliche Rindenflächen und gewundene Furchen mit helleren Kanten ersetzt. Die stehenden Fichten liefern die zusätzlichen Rindenlicht- und Pilzfarben; der Ritterstamm liefert geschichtete Jahresringe, schiefe Risse und Splitter. Neu sind Astlöcher, ein kleines morsches Loch, freiliegende Holzfasern, Erde zwischen kräftigeren Wurzelfingern, unregelmäßige Moospolster und abgestufte Pilzkonsolen. Die acht Ansichten, Abmessungen, Anker, Kollisionswerte und Streuungsdaten sind unverändert. Vorschau neben den echten Referenzen: `tools/preview_logs_art.tscn`; eine vorhandene `/tmp/fallen-logs-before.png` dient dort optional als Vorher-Bild.

`FallenLog` zeichnet das Modell nach seinem eigenen Fußanker in der Y-sortierten Props-Ebene. Eine flache Bodenkapsel folgt der Richtung und Länge des tatsächlichen Stamms. Es gibt keine Sammelfunktion, Beute oder E-Interaktion. Die Mitte der oberen Stammfläche ist ein niedriger Sitzplatz für Krähen; Nacht- und Fluchtsitzplätze bleiben in den Baumkronen.

## Verteilung und Streaming

`FallenLogScatter.candidate` bereitet pro 8×8-Tile-Zelle einen unabhängig geseedeten Kandidaten vor. Wald erhält etwas mehr, Glasklippen erheblich weniger Stämme. Platzierung prüft die ganze Strecke auf ebenen Boden, Land, größere Pflanzen/Steinbetten und freizuhaltende Wege/Storyflächen. Auch verschobene oder skalierte Editor-Props werden berücksichtigt.

Der kooperative Chunk-Aufbau führt die 16 möglichen Kandidaten einzeln aus. Stämme werden erst beim atomaren Commit sichtbar und kollidierbar; Abbruch entsorgt die vorbereiteten Nodes. Chunk-Entladen entfernt sie samt Kollision und Sitzplatz. Gleicher Seed und gleiche Weltbearbeitung ergeben beim Wiederladen dieselben Positionen und Ansichten. Die bestehende Vegetation, Gegner und Beutewürfe erhalten keinen anderen Zufallsstrom.

## Kleine Tiergeschichten

`WildlifeEvents` wählt als Host selten eine Begegnung zwischen bereits vorhandenen Tieren aus. Es erzeugt dafür keine Tiere vor den Augen der Spieler. Die Bewegung nutzt die bestehenden zuverlässigen Netzwerkaktionen für Hasensprünge, Krähenflug und Säugetierbewegung.

1. **Hase verscheucht Krähe:** Ein ruhiger Hase nähert sich in kleinen Sprüngen. Die Krähe weicht ein bis zwei Schritte aus und fliegt schließlich zu einem gültigen Ziel. Funktioniert tagsüber mit bodennahen Krähen.
2. **Hasen spielen:** Zwei ruhige Hasen folgen einander kurz in versetzten Sprüngen und kehren anschließend zu Grasen beziehungsweise Putzen zurück.
3. **Fuchs jagt Hasen:** Ein aktiver Fuchs lauscht, verfolgt einen echten Hasen über begehbare Teilstrecken und versucht höchstens zwei Sprünge. Der Hase behält seine normale Flucht-KI. Nur tatsächliche Nähe während des Fuchssprungs löst einen Fang aus. Bei Hindernissen, Unterbrechung oder Zeitablauf entkommt die Beute. Der Fang blendet den Hasen kurz unter dem Fuchs aus und entfernt ihn über den normalen Host-Despawn; ohne Blut, Spielerbeute oder Erfahrung. Der Fuchs geht kurz in die vorhandene Fress-/Suchpose über.

Spielerannäherung, Raubgegner und bestehende Angstreaktionen können die Begegnungen unterbrechen. Dialoge, Karten und Storysperren verhindern neue Begegnungen beziehungsweise beenden laufende. Anschließend erhalten die Tiere ihre normale Autonomie zurück. Pro Welt läuft höchstens eine solche Szene. Anfangswerte in `data/wildlife_events.json`: Auswahl alle 20–45 Sekunden, maximal acht Sekunden Ereignislänge, 65–115 Sekunden Teilnehmerpause, Beobachtungsentfernung 75–340 Pixel. Die Nähe geeigneter Tiere ist zusätzlich Voraussetzung; daher findet nicht bei jedem Auswahlversuch ein Ereignis statt. Füchse behalten ihren vorhandenen Dämmerungs-/Nachtrhythmus.

## Prüfung

- `tools/test_logs_events.tscn`: echte Texturgrößen, Stammpopulation/Kollisionen/Freiräume, stabile Wiederladung, Krähenflug, Hasenspiel, Abbruch durch Angst und Cutscene, Fang ausschließlich bei körperlichem Kontakt und niedriger Stamm-Sitzplatz.
- `tools/test_streaming_performance.tscn`: atomare Aktivierung, Abbruch, Wiederladen, Editor-Neuaufbau und begrenzte Vorbereitungsarbeit.
- Bestehende Hasen-, Krähen- und Waldsäugerprüfungen: 211, 814 beziehungsweise 53 Prüfungen ohne Fehler. Die ersten beiden laden wie die Waldsäugerprüfung die Welt-Szene vor ihren eingebetteten Welt-Testklassen vor.

Weltvorschau aus dem Integrationstest: `/tmp/fallen-logs-world.png`.

## Umgefallene Stämme abbauen (2026-11-06)

Mit der Axt (`axe_basic`) lassen sich Stämme in drei Treffern zerlegen (`data/harvest.json` `fallen_log`: Tannenholz, Stöcke). Der gefällte Stamm verschwindet dauerhaft, Vögel auf ihm fliegen ab. Ein Stamm trägt eine Trefferkapsel auf Physik-Layer 5 entlang seiner Mittellinie. Details und Test: [docs/flora.md](flora.md) („Klee mähen und Stämme hacken“), `tools/test_harvest.tscn`.
