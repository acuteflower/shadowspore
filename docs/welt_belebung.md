# Welt beleben und Tag/Nacht-Stimmung (2026-11-10)

Autonomer Durchgang: die Wiese soll handplatziert statt generiert wirken, der Tag poppiger, die Nacht dunkler, unheimlicher, gefährlicher.
Nichts davon verändert Spielregeln, Speicherstände oder das Netzwerkprotokoll; alles Neue ist Daten, Generator-Ebene oder lokal/kosmetisch.

## 1. Tiere (data/wildlife.json)

| Gruppe | vorher | jetzt |
|---|---|---|
| Hasen (`max_loaded`, `chunk_chance`) | 36, 0.72 | 44, 0.80 |
| Vögel gesamt (Krähen/Raben/Eule/Wiedehopf teilen sich ein Budget) | 8 | 11 |
| Krähen `chunk_chance` | 0.22 | 0.30 |
| Waldsäuger gesamt | 8 | 10 |
| Schmetterlinge (Budget, Chance) | 10, 0.32 | 16, 0.50 |
| Bienen / Schnecken / Marienkäfer / Motten | 24 / 18 / 12 / 14 | 28 / 22 / 16 / 18 |
| Glühwürmchen (`Fireflies.COUNT`) | 56 | 76 |

Seltenheits-Obergrenzen (1 Eule, 2 Wiedehopfe) blieben. Die Tests `test_corvids`, `test_meadow_birds`, `test_woodland`, `test_tiny_wildlife` kennen die neuen Zahlen.

## 2. Pflanzen und Komposition (PropGenerator, test_level)

- Zwei neue Cluster-Ebenen am Ende der Tabelle (Ids 31, 32 – bestehende Ebenen behalten jede Zufallszahl):
  - `bloom_drift`: eine Blumeninsel (12–20 Blumen einer Art, ~22 % einer Akzentart, ein paar Grasbüschel) als elliptischer Streifen; Art nach Licht/Schatten/Feuchte gewichtet.
  - `boulder_nook`: ein großer Fels mit eigenem kleinen Garten am Fuß (Gras, passende Blumen, Pilz im Schatten, Kiesel, gelegentlich ein Busch).
- `_skirt()`: gemeinsamer Rock aus Kleinpflanzen; auch an jeden Einzelbaum (2–5) und an kleine Einzelfelsen (2–4) gehängt, damit nichts mehr „allein im Rasen steht“.
- Alles hat niedrige Priorität, verdrängt also nie Bäume, Felsen oder Beerensträucher (A/B gegen HEAD: Bäume unverändert, Gesamtprops +9 % vor der letzten Dichteanhebung).
- Bodenkacheln (`_pick_tile_kind`): mehr Blumenwiese in lichten Zonen (`0.065 + 0.26 * lush`), mehr Büschel/Farn im Schatten.

## 3. Tag: poppiger (data/mood.json, mood_grade, ground_tone)

- Höhere Vibranz (Mittag 0.44) und Kontrast (0.10), wärmeres Licht, kühlere Schatten – das Bild bekommt Farbtrennung statt Einheitsgrün.
- **Boden-Farbdrift** (`ground_tone.gdshader`): großräumiges Rauschen (~340 px) verschiebt den Rasen regional zwischen gelblich-warm und bläulich-kühl; die Wärme wächst mit der Goldenen Stunde. Aus im Hexenwald (`1 - gloom`).

## 4. Nacht: düsterer, unheimlicher, gefährlicher

- Dunklere, kältere Nacht (Schatten `0.74/0.82/1.34`), stärkere Blüte (Bloom 1.0) für Leuchtpflanzen und Lichter.
- **Vignette** (`mood_grade.gdshader`, neues Uniform `vignette`, pro Schlüssel in mood.json): nachts sinkt der Bildrand in den Schattenton (0.62), Tag nur 0.10–0.16, Innenräume 0.30, Hexenwald 0.55. Die Dunkelheit „schließt sich“ um sie.
- **`NightWatchers`** (src/fx/night_watchers.gd, von `DayNight` angehängt): bis zu vier Augenpaare (magenta, im Hexenwald hexengrün) in Büschen am Sichtrand, die ihr mit dem Pupillenpunkt folgen, blinzeln und verschwinden, wenn sie näher als 62 px kommt, Licht in der Nähe ist oder der Tag anbricht. Rein kosmetisch und lokal: kein Netzwerkknoten, keine Kollision, kein Schaden, kein Ton. Nicht in Räumen/der Mine, nicht im Licht der Stadt (+28 px Rand).
- Mehr Glühwürmchen (76) halten die Nacht lebendig, damit die Dunkelheit nicht leer wirkt.

## 5. Prüfen

- Vorschau: `Godot --rendering-driver opengl3 --path . tools/preview_daylight.tscn -- --dir=/abs --times=0.5,0.757,0.0 --at=786,679 [--watchers]`.
- Regressionen: Streaming-Test ohne Leistungsverlust; Wildlife-Tests mit den neuen Budgets grün.
- Bekannte, **vorher schon** fehlschlagende Tests (auf HEAD verifiziert): `test_forest`, `test_meadow_birds` (Einzelfall), `test_wind`, `test_night`, zwei Checks in `test_tiny_wildlife`, Streaming (9 Checks). `test_daylight` „pollen bounds respect camera zoom“ ist nicht gegen HEAD gegengeprüft.

## 6. Grenzen

- Nur wenige Orte wurden im Bild begutachtet; Gesamtwirkung in langem Spiel, Multiplayer-Last und die Augenpaare mit echtem Spieler sind ungetestet.
- Alle Zahlen sind Stellschrauben (wildlife.json, mood.json, Konstanten in night_watchers.gd), keine endgültigen Werte.
