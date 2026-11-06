# Kleine Wiesenpflanzen (flora)

Vierzehn neue Pflanzen, alle in `data/plants.json`, alle `Flora` (src/entities/props/flora.gd, erweitert `Bush`: Durchlaufen bremst und raschelt, Sichel erntet, E pflückt, Zustand `{"h","p","k"}` und Nachwachsen laufen über `WorldLevel`). Frames 40x34, Füße (20, 31), Kunst: `python3 tools/art_flora.py [preview.png]` (stdlib, schreibt Sheets, `_glow`-Sheets und 9 Item-Icons; danach `Godot --headless --import`).

| Pflanze | Wo | Ernte | Besonderheit |
|---|---|---|---|
| Mondglöckchen `moonbell` | Schatten, Lichtungen | E: `moonbell` (Mondglocke) | Glöckchen leuchten nachts türkis, Glühwürmchen, Lichtpfütze |
| Wundblatt `wound_leaf` | offene Wiese | E: `wound_leaf`, heilt sofort 8 | Tautropfen glitzern, violette Ähren |
| Wispersaat `puffseed` | offene Wiese | E: `seed_fluff` | beim Durchlaufen lösen sich Samen und treiben im Wind (`puff`, 7 s Pause) |
| Leuchtfern `glowfern` | Schatten | E: `fiddlehead` (heilt 3 + 12/10 s); Sichel: `fern_frond`, Fasern | Sporen und Farnsprosse leuchten, Lichtpfütze |
| Rohrkolben `cattail` | Ufer (Schilfbeete) | Sichel: `reed` | biegt sich stark im Wind; `reed` x4 = Seil (Rezept `rope_reed`) |
| Sonnenwende `sunbloom` | offene Wiese, Felder | E: `sun_seed` (heilt 10) | Kopf folgt der Sonne (Ost/oben/West), schließt sich nachts und lässt sich dann nicht pflücken (`sun`, Sheet-Zeilen 0-4) |
| Leerenblüte `voidbloom` | 4-12 Kacheln vom Küstenrand, selten (~60 auf der Karte) | E: `void_bloom` (uncommon, Material) | magenta Adern, pulsierendes Licht |
| Erdknolle `earth_tuber` | offene Wiese, kleine Äcker | E "AUSGRABEN": `earth_tuber` (heilt 6 + 10/8 s) | nach dem Graben bleibt ein Erdhaufen |
| Glutmöhre `ember_carrot` | einzeln in der Wildnis, eher am Licht | **ausziehen** (E): `ember_carrot`, heilt 4 + 22/14 s, uncommon | glimmende Wurzelschulter, Wärmelicht; zurück nach 5 Tagen |
| Nachtrübe `night_beet` | einzeln, tiefer Schatten | **ausziehen** (E): `night_beet`, heilt 16, uncommon | dunkle Rübe mit türkisem Schimmer in den Ringen; zurück nach 6 Tagen |
| Nebellilie `mist_lily` | Schatten, feuchtes Ufer, Teppiche | E (nur nachts): `mist_lily` (Nebelblüte, uncommon) | tagsüber zu (Knospe, nicht pflückbar), öffnet sich in der Dämmerung, streut dann langsam glimmenden Blütenstaub (`bloom: "night"`, Sheet-Zeilen 0 offen, 1 zu, 2 gepflückt) |
| Funkenmohn `spark_poppy` | offene Wiese, Mohnfelder | E: `spark_poppy` (Mohnfunke) | beim Durchlaufen stieben Glutfunken nach oben (`puff` + `puff_rise`), Blütenränder glimmen nachts; einige Pflanzen mit hängenden, behaarten Knospen |
| Glutmorchel `ember_morel` | Schatten, Birkenränder, kleine Gruppen | E: `ember_morel` (heilt 2 + 14/7 s) | Wabenkappe mit Gruben, die nachts wie Glut leuchten; Art `tools/art_shrooms.py` |
| Mondschirm `moon_parasol` | Schatten, selten als **Feenring** (7-10 Schirme im Kreis, Glimmkappe in der Mitte; `fairy_ring`) | E: `moon_parasol` (uncommon, Material) | blass-lila Schirm mit Lichtsaum; beim Durchlaufen stieben Sporen (`puff`) |

**Wurzeln ziehen (`pull: true`):** `Flora.interact` startet `Player.begin_pull` (Sheet `player_pull.png` + `_blood`, 12 Frames, 1 s, alle 8 Richtungen; Keyframes `PULL_KEYS` in `tools/art_hero3d.py`, `python3 tools/art_hero3d.py pullonly` schreibt Sheet, Blutmaske und Rig, `... pull out.png <sektor>` ist ein Kontaktbogen). Ellie geht in den Stand, greift mit beiden Händen ins Laub, stemmt sich tief, zittert, bei 0,52 s gibt die Wurzel nach: sie wird zurückgeworfen, taumelt einen Schritt, fängt sich und schüttelt die Erde ab. Das Laub zittert lokal immer stärker (`_tug_from`), beim Ruck fliegt Erde (Partikel), Kamerarütteln, die Wurzel springt als Drop heraus, ein Erdloch bleibt (Zeile 2 des Sheets). Erzeugung: Ebene `lone_root` (Zellen 18, mehr im Schatten; ~135 Möhren, ~70 Rüben auf der Karte). Capture: `Godot --rendering-driver opengl3 --path . tools/preview_pull.tscn -- --dir=/abs [--kind=night_beet]`.

Rahmen: kein Frame darf die Kanten des 40x34-Bildes berühren; `art_flora.py` bricht sonst ab (`fit`), die Sonnenwende (vorher oben abgeschnitten) ist entsprechend kleiner gezeichnet.

Erzeugung: `PropGenerator` Ebenen `lone_flora` (Einzelpflanzen, Zellen 7) und `flora_patch` (Gruppen 4-9, Sonnenfelder größer, Schilf am Ufer, Leerenblüten am Rand); Auswahl nach Schatten/Offenheit/Ufer/Küstenabstand (`_flora_kind`). Prioritäten 0.15-0.35: sie weichen allem Bestehenden, ändern also nichts, was vorher stand. Items verkauft Gustav (`shops.json` sell).

Test: `Godot --headless --path . tools/test_flora.tscn` (Sheets, Items, Erzeugung über die ganze Karte, Sonnenwende-Posen, Samenflug).


## Mondbirke (`birch`)

Neuer Baum (`tree.tscn`, 6 Größen 88-194 px, drei Blattpaletten: frisches Grün, Herbstgold, Silberteal; ein Zwilling, schiefe und alte hohle mit Pilzen und violetten Narben). Art `python3 tools/art_birch.py [preview.png]`: weiße, violett getönte Rinde mit dunklen Strichen und Schwarzfuß, Äste, die sich bogen, lange feine Zweige mit Blattbüscheln, die in der Luft hängen. Magie: Laternenblätter und hängende Samen glimmen nachts, goldene Blätter fallen dauernd (`petals`), warmes Licht ab der vierten Größe. E pflückt `birch_leaf`, Axt gibt `birch_wood`, `birch_bark`. Erzeugung: `birch_grove` (Gruppen mit alten in der Mitte und jungen am Rand, Glimmkappen am Fuß) und `lone_birch`; ~1200 auf der Karte. Krone schwingt im Baumwind (`sway`).

## Wind für alle neuen Pflanzen

`WorldWind` setzt die Shader-Globals `g_wind_dir`, `g_wind_gust`, `g_wind_clock` (project.godot). `Flora` benutzt `flora_wind.gdshader` (+ `_glow`-Variante, Include `flora_wind.gdshaderinc`): die Zeilen über der Bodenzeile verrutschen in ganzen Pixeln, je höher desto mehr, derselbe Böenpuls wie bei Gras und Büschen, Nachbarspalten laufen versetzt, jede Pflanze hat ihre eigene Phase, Stärke = `sway` aus plants.json. Gilt für alle Blumen, Wurzeln, Farne, Pilze und Rohrkolben, das Leuchtbild bewegt sich mit. Das alte Seiten-Kippen (`skew`) bleibt nur noch für das Rascheln beim Durchlaufen. Bäume schwingen weiter über `tree.gd`, Kleeblüten über `MeadowDetails` (mit Kontaktbiegung).

## Kleeblattfelder (`CloverField`)

Pro Chunk ein bis zwei kleine Felder (3-7 Kacheln, nur auf offener, flacher, freier Wiese, `WorldLevel._build_clover_fields`). Ein Feld ist keine Textur auf dem Boden, sondern eine Menge **stehender Büschel** (dreiblättrige Blätter an dünnen Stielen, höhere mit Blüten), in 6-px-Streifen als MultiMesh gebündelt; jeder Streifen ist ein eigener y-sortierter Knoten in der Props-Kette. Ellie steht deshalb *im* Feld: Streifen vor ihr verdecken ihre Unterschenkel. Die Büschel biegen sich von Ellie weg (stärker beim Laufen, beruhigen sich langsam) und wehen im Wind (`clover_clumps.gdshader`); eine zweite, unshaded Schicht glimmt nachts (Tautropfen, Blütenherzen, void-violette Spitzen).

Zufall: `plan` zieht alles aus dem Seed des Feldes, und `_make_atlas` malt die Büschelbilder **dieses** Feldes neu: Blattform (rund, breit, spitz), Größe, Anzahl, Höhe, Chevron, Tau, Palette (aus den Weltrampen, mal olivstichig), Blütenfarben (1-3 von 6), Umriss, Dichte, Fleckigkeit, selten ein vierblättriges Kleeblatt. Vorschau: `tools/preview_clover.tscn -- --out=/abs.png [--seed=n]`, Orte: `tools/find_clover.tscn -- --at=x,y`.

## Wind-Wackeln beim Laufen (Fehler behoben)

Die Wind-Shader haben Position und Phase aus der Modellmatrix und einem Hash der Position gelesen; sobald die Kamera mitlief, sprangen die Phasen. Jetzt hat jede Pflanze ihr eigenes Material mit festen Uniforms (`origin`, `phase_seed`), Kleestreifen bekommen `band_origin` und den Versatz im Instanz-Datenfeld. Nichts im Wind hängt mehr von der Kamera ab.
