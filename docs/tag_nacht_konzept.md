# Tag und Nacht auf 10/10 – Änderungskonzept

Status: **Phasen 0–4 und 6 gebaut, Phase 5 bewusst zurückgestellt (siehe Schlussmeldung in der Konversation).** Vor jeder Phase bitte abstimmen (Projektregel: keine Systeme bauen, die nicht besprochen sind). Grundlage: Analyse „düster mystisch nachts / lichtern und leuchtend tags“ plus Gegenprüfung im Code (`TimeManager`, `DayNight`, `ground_tone.gdshader`, `Fireflies`, `design_guide.md` §6).

## 1. Bewertung der Analyse

**Stimmt und ist brauchbar**
- Nacht ist der Maßstab: Tint `0.38/0.41/0.68`, Eigenleuchten der Flora, `NightLight`, Glühwürmchen, Weltrand, Flussplankton. Der Tag hat dafür kein Gegenstück.
- Der Tag ist im Kern „neutral“: `KEY_COLORS` steht von 0.28 bis 0.72 praktisch auf 1,0 (Mittag exakt weiß); Luftleben tagsüber = höchstens 8 Windpartikel, nachts 56 Glühwürmchen + Wasser- und Randeffekte.

**Korrekturen**
- **`Color(1.02, …)` geht nicht.** `CanvasModulate` multipliziert und klemmt bei 1,0 (`project.godot` hat kein HDR-2D). Eine „warme“ Tönung kann nur Blau absenken, also eher abdunkeln. Mehr Leuchten kommt aus Shadern und additiven Ebenen, nicht aus dem Tint. HDR-2D einschalten wird verworfen (Eingriff in die ganze Pipeline, Metal-Probleme sind in `CLAUDE.md` vermerkt).
- **„Mittag ohne Tönung“ ist bewusst** (`design_guide.md` §6). Jede Änderung dort muss auch die Tabelle im Guide ändern.
- **Die Noten sind nie gesehen worden.** Der Screenshot-Test der Analyse wurde abgebrochen; alles stammt aus dem Lesen von Code. „10/10 Nacht“ ist also eine Annahme. Daher beginnt das Konzept mit Vergleichsbildern.
- „Feinde: tagsüber seltener“ steht so nicht im Code; Nachtstärke der Gegner ist laut Plan noch offen. Die Zeile wird nur optisch behandelt.
- Die Vorschläge decken nur die schwachen Tag-Zeilen ab. Die Nacht-Zeilen mit 9/10 (Wiese, Wildlife) und die Feinde (Tag 8) haben in der Analyse keine Maßnahme.

## 2. Was „10/10“ heißt (prüfbar statt Bauchgefühl)

Je Zeile ein Abnahmebild bei fünf Zeiten (Nacht 00:00, Sonnenaufgang 06:30, Mittag 12:00, Goldstunde 18:30, Nacht-Wiese mit Leuchtflora) und diese Kriterien:

| Zeile | Ziel (10/10) |
|---|---|
| Licht & Himmel Tag | Mittag liest sich als Sonne, nicht als „kein Filter“: sichtbarer Lichtüberschuss auf Sonnenflecken, Kontrast aus Licht und Wolkenschatten |
| Wiese Tag / Nacht | Tag: Licht wandert sichtbar über die Wiese. Nacht: Mondlicht und Bodennebel geben dem Violett Tiefe |
| Flora Tag | Leuchtpflanzen „schlafen“ erkennbar (geschlossene, glitzernde Knospen), kein totes Kachelbild |
| Weltrand Tag | Licht fällt in die Leere; goldene Glints an der Kante |
| Gewässer Tag | Funkelnde Reflexe, Kaustik in Furten, Schaumglanz |
| Wildlife Tag / Nacht | Tiere sind sichtbar im jeweiligen Licht eingebunden (Glanzkanten, Schlaf- und Wachzustände), plus Ton |
| Feinde Tag | Schattenwesen wirken im Sonnenlicht „angefressen“ (Entscheidung nötig, siehe Phase 5) |
| Atmosphäre Tag | Lichtstaub, Pollen, Strahlen füllen die Luft ähnlich dicht wie nachts die Glühwürmchen |

Nacht-Zeilen, die schon 10 sind, dürfen nicht schlechter werden (Vergleichsbild vorher/nachher).

## 3. Leitregeln für alle Änderungen

1. **Spiegelprinzip:** Nacht = das Leuchten kommt aus den Dingen. Tag = das Licht kommt von oben, liegt auf Kanten, Wasser und in der Luft. Neue Tag-Effekte folgen den bestehenden Nacht-Regeln (Quelle strahlt selbst, kleine ungetönte Pixel, Dither, kein weicher Verlauf, kein Rauch).
2. **Eine Zeitkurve für alles:** `TimeManager.sun_amount()` (0 Nacht … 1 Mittag, glatt durch die Dämmerung) und `golden_amount()` (Spitze bei Sonnenauf- und -untergang), Gegenstück zu `night_amount()`. Kein Effekt rechnet eigene Tageszeit-Kurven.
3. **Kosmetisch und lokal:** jeder Peer rechnet sie selbst (wie `Fireflies`), nichts davon ist Gameplay, wird repliziert oder gespeichert.
4. **Budgets:** feste Obergrenzen pro Effekt, nur im Bildausschnitt (+40 px); gegen `docs/performance.md` messen. Wo möglich in bestehende Shader (`ground_tone`, `relief`, `river_*`, `glow_layer`) statt neuer Vollbild-Pässe; höchstens **ein** neuer Quad (`SunGlow`).
5. **Unterdrückung wie bei den Windpartikeln:** keine Tag-Effekte in Innenräumen und in der Mine (immer Nacht), bei UI-/Story-Sperren, Karte, Inventar.
6. **Lesbarkeit und Komfort:** Warnflächen bleiben ungetönt und dominant; Glints ≥ 0,4 s Lebensdauer mit Ein-/Ausblenden, höchstens 3 pro Sekunde je Bildbereich (kein Flimmern).
7. **Neu erfunden wird nur, was der Nutzer bestätigt** (Mond, Fledermäuse, Tag-Verhalten der Gegner stehen unten als Entscheidungen).

## 4. Phasen

### Phase 0 – Fundament und Messung
- `sun_amount()` / `golden_amount()` in `TimeManager` (ein paar Zeilen, an `night_at` angelehnt).
- Capture-Workflow (Preview-Szene mit `--capture=`, Vorbild `tools/check_water_capture.py`, OpenGL-Kompatibilität wegen der Metal-Abstürze), Zeit per `TimeManager.set_time`. Vorher-Bilder aller Zeilen. **Erst danach sind die Noten echt.**

### Phase 1 – Mittagslicht (größter Hebel: Licht & Himmel, Wiese Tag)
- `ground_tone.gdshader`: Uniform `sun`; sonnenbeschienene Dither-Flecken bekommen eine zusätzliche hellere Stufe, Schattenflecken bleiben. Kontrast erzeugt „Leuchten“, nicht der Tint.
- Wandernde **Wolkenschatten** (aus dem bestehenden Nebelschatten-Muster, tags größer und träger).
- `SunGlow`: ein einziger additiver, gedithert gestufter Quad (warmes Gold, sehr niedrige Stärke, Spitze bei `golden_amount`), unshaded, im Level unter dem HUD.
- `KEY_COLORS`: Mittag höchstens `1.0/0.99/0.95`, Morgen und Nachmittag nachziehen. `design_guide.md` §6 Tabelle anpassen.

### Phase 2 – Tagesluft (Atmosphäre Tag)
- `DayMotes` als Geschwister von `Fireflies` (gleiche Mechanik: nur im Bild, Einblenden über `sun_amount`): höchstens ~40 Pixel-Staubkörner in Blassgold/Weiß, Drift aus `WorldWind`, mehr über Blumenwiese und in Strahlen, Goldstunde = gold und rückbeleuchtet.
- Überblendung im Dämmern: Staub blendet aus, während Glühwürmchen einblenden (nie beide voll).
- Die acht Windpartikel (Blätter, Samen, Blüten) bleiben unverändert und eigenes Budget.

### Phase 3 – Glanz (Gewässer, Flora, Weltrand Tag)
- Wasser (`river_water.gdshader`): seltene helle Funkelpixel auf den Reflexclustern, Kaustik-Lichtmuster auf flachen Furten, Schaumglanz an Felsen.
- Wiese: **Morgentau** an den Halmspitzen (`blade_shift`), stark am Morgen, bis ~08:30 weg.
- Leuchtflora tags (`glow_layer.gdshader`): statt „totem Boden“ geschlossene, schwach funkelnde Knospenpixel; Aufwachen/Einschlafen als Übergang bei Dämmerung (Leuchtkurve bleibt `night_amount`).
- Kristalladern in Wänden (`relief.gdshader`, Vein-Muster): tags einzelne Sonnenfunken statt Nachtglühen.
- Weltrand (`void_edge.gdshader`): goldene Glints an der Bruchkante, ein Lichtschaft, der in die Leere fällt.

### Phase 4 – Waldlicht
- Lichtkringel in beschatteten Waldzonen im `ground_tone` (über die vorhandene Wildheits-Zone, windbewegt), keine Positionsabfrage pro Baum.
- Dünne diagonale Lichtstrahlen (additiv, im Bildausschnitt, nur Morgen/Abend) in Anlehnung an die Strahlen der Innenräume.

### Phase 5 – Ränder und Lebewesen
- Wildlife Tag/Nacht: bestehende Zustände sichtbar ins Licht setzen (zarte Kantenlichter tagsüber, Schlafzustände nachts nutzen). **Keine** leuchtenden Augen bei normalen Tieren (Regel bleibt).
- Feinde Tag (**Entscheidung nötig**): Schattenwesen werden bei Sonnenlicht nur optisch „angefressen“ (weniger Emission, aufsteigende Violett-Fetzen, Randlicht). Standard „alle Schattenwesen leuchten magenta“ bleibt; Gameplay ändert sich nicht.

### Phase 6 – Nacht-Feinschliff und Ton
- **Mondlicht** (**Entscheidung nötig**): kühles, spärliches Glitzern auf Wasser und Boden, Bodennebel in Mulden. Wiese Nacht 9 → 10.
- Ton als Hebel für beide Hälften: Tagesbett (Vögel, Bienen, Wind) und Nachtbett (Grillen, ferner Leerenton), per Skript wie `tools/audio_*.py`, synthetisierte Platzhalter, Übergang über `sun_amount`/`night_amount`.

### Phase 7 – Abnahme
- Nachher-Bilder zu den fünf Zeiten gegen die Kriterien aus Abschnitt 2; erst wenn jede Zeile besteht, wird sie 10 genannt. `CLAUDE.md` und `design_guide.md` §6 nachziehen.

## 5. Reihenfolge nach Wirkung/Aufwand

1 Phase 0 → 1 → 2 → 3 (Wasser, Tau) → 4 → 5 → 6 → 7. Phase 1+2 allein heben Licht & Himmel Tag und Atmosphäre Tag am stärksten (die zwei schwächsten Zeilen).

## 6. Offene Entscheidungen

1. Mond und Bodennebel (Phase 6) gewünscht?
2. Schattenwesen am Tag optisch geschwächt (Phase 5)?
3. Ton-Betten jetzt oder später?
4. Mittag minimal warm (`1.0/0.99/0.95`) oder bewusst neutral lassen und nur über Shader aufhellen?
