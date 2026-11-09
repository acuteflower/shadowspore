# Pflanzenleben: Fangblume, Samenflug, Nass und Trocken, Leerenfäule, Unterholz-Tiere

Fünf Ergänzungen der Pflanzenwelt. Alles ist hostgesteuert, wo es Spielzustand ist (Stich, Samen, Fänge), und rein deterministisch,
wo es nur Optik ist (Nässe, Fäule, Tiere auf dem Busch). Test: `tools/test_plant_life.tscn` (Godot headless), Kunst:
`py -3 tools/art_plant_life.py [vorschau.png]`.

## 1. Fangblume (`snapper`, `Snapper`)
- Kleine Nachtblume mit zwei Zahnkiefern und leuchtender Lockperle (Blatt-Sheet 3 Varianten x 3 Zeilen: offen, halb zu, Knospe; `snapper_glow.png` nur Leuchtpixel;
  `snapper_stripped.png` abgeschnittene Stängel). Violett, türkis, rot.
- Tags geschlossen und harmlos. Ab `snapper.open_from` (0,45 Nachtanteil) geht sie auf. Gelegentlich flattert eine Motte heran und wird gefressen (reine Show, jeder Peer für sich).
- **Stich:** Nur der Host entscheidet. Wer im `range` (15 px, geduckt halb so viel) bleibt, sieht erst die Lockperle aufblitzen (`LURE_FLARE` 0,35 s, bei jedem Peer für den eigenen Spieler schon ab dem doppelten Abstand),
  dann schnappt sie: 4 Schaden, 3 s Abklingzeit je Spieler, `WorldLevel._rpc_thing_fx` lässt alle die Animation sehen.
- **Im Licht der Stadt schläft sie** (`TownManager.light_depth > -4`). Deshalb ist sie nur am dunklen Rand gefährlich.
- **Wo sie wächst:** selten wild im dunklen, feuchten Schatten (Layer `lone_snapper`, Chance `0,04 + 0,22 · Schatten · Feuchte`) und **am Rand des Stadtlichts**: Jeden Sonnenaufgang setzt `PlantSowing._edge_round`
  bis zu 10 Fangblumen 10-44 px außerhalb des Lichtkreises. Wächst das Licht über eine hinweg, verwelkt sie.
- Mit der Sichel erntbar (2 Hiebe, Blätter und Pflanzenfaser), wächst wie ein Busch nach.

## 2. Samenflug (`PlantSowing`, Knoten `PlantSowing` des `WorldLevel`)
- Pflanzen mit `sow` {`chance`, `range`, `lifespan`} in `data/plants.json` streuen jeden Sonnenaufgang (Host) Samen: Wispersaat, Funkenmohn, Mondglöckchen, Nebellilie, Sonnenwende, Wundblatt.
  Gepflückte Pflanzen haben keinen Samen. Auf nassen Tagen ist die Chance x1,5, auf trockenem Boden bis zu x0,4.
- Der Samen fliegt als Bogen (1,2 s) zu einem freien Feld, dort steht danach eine junge Pflanze der gleichen Art (60 % Größe, nach 4 Tagen voll). Nach `lifespan` Tagen verwelkt sie wieder.
- Regeln (`cell_ok`): geladener Chunk, `town_probe` frei (Land, eben, kein Wasser, nichts im Weg), mindestens 14 px (Bäume/Felsen 26 px) Abstand zu anderen, höchstens 10 gesäte je Chunk, 260 insgesamt.
- Zustand `sown` (Zelle -> `{k, v, d, e}`), per RPC an alle, Snapshot für Beitretende, im Spielstand als `"s:x,y"` unter `things`. Gesäte Pflanzen sind normale `WorldProp`s ihres Chunks (Pflücken, Ernten und Nachwachsen wie sonst).

## 3. Nass und trocken (`Moisture`, `PropGenerator.damp_at`)
- **Boden:** `damp_at(tile)` 0..1 aus Nordhang/Klippenfuß (feucht), Wasserrand (feucht), Höhe (trockener), etwas Rauschen. Pilze, Pilzgruppen und Fangblumen nehmen mit der Feuchte zu, Büsche, Wildblumen und Blumenflecken
  werden an trockenen Hängen bis auf 45 % spärlich. Bodenbewuchs: bei Feuchte > 0,7 mehr Moos/Farn, bei < 0,18 Stroh und dünnes Gras.
- **Wetter:** Etwa jeder dritte Tag ist ein nasser Tag (aus Weltseed und Tagnummer, überall gleich), ebenso der Tag nach einer Nebelnacht. `Moisture.wetness()` ist beim Morgengrauen 1 und trocknet bis zum Abend auf 35 %.
  Wirkung: die Welt wird etwas kühler und dunkler (`DayNight`), Tau-Tropfen auf dem Boden (`g_dew`), Pilze/Kräuter wachsen einen Tag früher nach, mehr Unterholz-Tiere (besonders Schnecken), Samen keimen besser.
- Kein Regen als Animation: Nässe zeigt sich über Licht, Tau und Pflanzenmenge.

## 4. Leerenfäule (`WorldProp._setup_blight`)
- Kleine Pflanzen (keine Bäume/Felsen) bis 14 Felder vom Weltrand (die gebackene Küstenkarte kennt nur ±16) werden grau-violett und knicken ein (`blight` 0..1). In mondhellen Nächten glimmen sie violett
  (`blight · Nacht · (0,12 + 0,3 · Mondlicht)`). Pflanzen mit Glow-Sheet färben ihr Glühen um, die anderen bekommen einen Schimmer-Sprite.

## 5. Unterholz-Tiere (`LeafCritter`)

Kleine Entdeckungen im Laub: **Schimmerkäfer**, **Blattraupe**, **Laubschnecke**. Arten, Mengen und Zeitabläufe stehen in `data/leaf_critters.json`; die sechs geeigneten Pflanzenarten behalten ihren `critters`-Block in `data/plants.json`.

- **Verteilung:** 10–14 % Kandidatenwahrscheinlichkeit, zusätzlich ein zwei Tiles breiter freier Rand um jedes 16×16-Tile-Gebiet und höchstens ein Bewohner pro Gebiet. Das ergibt deutlich weniger als die früheren 20/40 % pro Pflanze. Weltseed, Zelle und Tag bestimmen Kandidaten, Art und Vorrang. Regen verdoppelt die Menge nicht mehr: Er erhöht den Schneckenanteil (16 → 58 % vor Pflanzenbias); Farn und Rohrkolben bevorzugen Schnecken.
- **Stabilität:** Alle Pflanzen eines Gebiets wählen aus derselben registrierten Menge. Gebiete teilen die 32-Tile-Streamingchunks exakt; während eines schrittweisen Commits bleiben Tiere verborgen. Erst `LeafCritter.settle_chunk` zeigt die endgültige Auswahl. Beim Fang oder Abernten rückt niemand nach. Die Auswahl prüft das intakte Ausgangsbild, damit auch nach Laden eines kahlen Busches kein Ersatz erscheint. Beim Entladen werden die Registrierungen entfernt.
- **Blattkontakt:** Gecachte, gegen das echte Sprite geprüfte Standplätze tragen den gesamten 9×5-Pixel-Körper einschließlich beider Blickrichtungen. Die Arten bevorzugen verschiedene Höhenbänder; auch alle Zwischenpunkte der kurzen Wege müssen passen. Hat eine Variante keine passende Fläche, bleibt sie unbewohnt. Sprite-Skew, Größenänderung und der zeilenabhängige Pixelwind von `Flora` werden übernommen. Die Tiere erhalten dieselbe Tageslichtschattierung wie die Pflanze.
- **Verhalten:** Käfer ruhen 26 Sekunden und bewegen sich höchstens 4 Pixel in 3,2 Sekunden; Raupen ruhen 31 Sekunden und ziehen sich in drei Kriechzyklen höchstens 3 Pixel weiter (4,8 Sekunden). Während des Fressens verdeckt ein Stück des echten Blatts den unteren Körper. Schnecken ruhen 34 Sekunden und brauchen 9 Sekunden für höchstens 3 Pixel. Ihre Fühler ziehen sich bei Nähe allmählich ein; das Haus bewegt sich währenddessen nicht. Käfer putzen sich und bewegen gelegentlich die Fühler. Die Bewegungsphase der Raupe ruht beim Stillstand.
- **Zeit/Mehrspieler:** Routen und lange Pausen folgen der gemeinsamen Spieluhr, nicht der Rechnerlaufzeit. Kleine kosmetische Gesten pausieren mit dem Spiel. Käfer und Raupen schlafen nachts, Schnecken bleiben etwas länger. Der Host entscheidet Fang und Abflug; alle Peers erhalten dafür den normalen zuverlässigen Prop-Zustand.
- **Berührung:** Durch einen Busch laufen lässt einen aktiven Käfer sichtbar seine Flügel öffnen und in einem kurzen Bogen mit Flügelschlag abfliegen. Der Host speichert `c = Tag + 1` ohne Beutedrop: Bis morgen bleibt die Pflanze ruhig, auch nach erneutem Laden oder späterem Beitritt.
- **Sammeln:** E **ABLESEN** fängt ein sichtbares Tier sicher; die Sichel hat weiterhin 55 % Fangchance. Danach ist es bis morgen weg. Erfolgreiches Einsammeln blendet es kurz aus, statt es zugleich wegfliegen zu lassen. Nacht, Abflug und Fang deaktivieren Prompt und Host-Fangprüfung gemeinsam. Eine eingezogene Schnecke bleibt am sichtbaren Haus sammelbar. Beeren haben weiterhin Vorrang beim E-Prompt.
- Items `shimmer_beetle`, `leaf_caterpillar`, `leaf_snail` bleiben **Flussköder** (`data/fishing.json`). Die übrigen Bienen, Marienkäfer, Schnecken, Falter und Schmetterlinge behalten ihre bestehenden Lebensräume; dieses System ergänzt sie sparsam.

Prüfung: `tools/test_leaf_critters.tscn` (Dichte/Abstand, alle 23 Pflanzenvarianten, kurze sichere Wege, Wind/Rascheln, Schnecken, Regen, Pause/Nacht, Fang, umgekehrte Ladereihenfolge, Sonnenaufgang und Cleanup), `tools/test_leaf_network.tscn` (zwei lokale Prozesse, `--server` auf einem: echter Prop-RPC, animierter Abflug und später Snapshot). Bestehende Regressionen: `test_plant_life`, `test_flora`, `test_wind`. Gerenderte Art-/Kontaktübersicht: `tools/preview_leaf_critters.tscn -- --capture=/abs/folder` schreibt Ruhe-, Kriech-, Wind-, Abflug- und Nachtbilder; die dort gezeigte Ansammlung aller Arten ist eine Werkbank, keine Spielverteilung.

## Werkzeug-Hinweis
Die Kunst (Fangblume, Icons) kommt von `tools/art_plant_life.py` (PIL, selbst gezeichnet). Der Projektregel nach sollte neue Kunst eigentlich von einem `gpt-6.1-terra`-Agent kommen; er war in dieser Sitzung
nicht verfügbar. Die Skript-Kunst ist ein sauberer Platzhalter in Stil und Palette der Wiese und lässt sich leicht ersetzen (gleiche Dateinamen und Frame-Größen).
