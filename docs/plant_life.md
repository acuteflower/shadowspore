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
- Büsche mit `critters` {`chance`} tragen heute (Zelle + Tag, deterministisch) vielleicht ein Tier: **Schimmerkäfer**, **Blattraupe** oder **Laubschnecke** (auf nassen Tagen doppelt so oft, mehr Schnecken).
  Käfer und Raupen schlafen nachts, Schnecken bleiben etwas länger. Die Tiere sitzen auf einer bemalten Blattkante des aktuellen Busch-Bildes (wenige Pixel im Code gezeichnet, kein Sheet).
- **E "ABLESEN"** fängt es sicher; ein **Sichelhieb** schüttelt es ab: 55 % Fang, sonst flieht es. Danach ist es bis morgen weg (Zustand `c` = Tag + 1).
- Items `shimmer_beetle`, `leaf_caterpillar`, `leaf_snail` (Icons 16x16) sind **Flussköder** (`data/fishing.json` `baits`, Gewichte pro Fischart).
- Ein Käfer fliegt auf, wenn man durch den Busch geht.

## Werkzeug-Hinweis
Die Kunst (Fangblume, Icons) kommt von `tools/art_plant_life.py` (PIL, selbst gezeichnet). Der Projektregel nach sollte neue Kunst eigentlich von einem `gpt-6.1-terra`-Agent kommen; er war in dieser Sitzung
nicht verfügbar. Die Skript-Kunst ist ein sauberer Platzhalter in Stil und Palette der Wiese und lässt sich leicht ersetzen (gleiche Dateinamen und Frame-Größen).
