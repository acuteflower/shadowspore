# Hexenwald: mehr Leben (Konzept und Stand, 2026-11-10)

Gehört zu `docs/hexenwald_konzept.md` (Gebiet, Boden, Gelände, Dämmer) und `docs/hexenwald_nebel_konzept.md` (Nebel, Trugbilder). Ziel: Der Hexenwald soll so lebendig wirken wie die Wiese, aber eigen bleiben. Er soll bewegt, geschichtet und mit Übergängen gestaltet sein, nicht einfach nur voller.

## 1. Befund (Ausgangslage)

- **Bäume:** Hexenulme und Bleichbaum hatten schon Leuchtzeilen (Augen, Irrlicht-Käfige, Pilze) und Lichtpools ab Variante 1. Ein früherer Befund hatte das übersehen. Es fehlten Glühwürmchen und jede Eigenbewegung. Der Bleichbaum schwankte mit 0,006, der Wind steht dort ohnehin (`exposure` 0,5). Jeder Stamm trug dieselbe lange grüne Zickzack-Ader.
- **Boden:** Es gab nur zwei Graskacheln, dünnes Gras (Dichte 0,3), kein Waldbett, keine Stämme, kein Laub. Im Bild wirkte die Fläche wie dunkelblauer Nachthimmel.
- **Kleine Bewegung:** Es gab keine Insekten (die suchen Wiesenblüten), keine Partikel und keine Pollen.
- **Fremdkörper:** Die häufigste Pflanze war der nur abgedunkelte Wiesenbusch (727 von rund 2500).
- **Rhythmus:** Fast jede Zelle war Wald, es gab keine Lichtungen. Alles leuchtete im gleichen Hexengrün.

## 2. Gebaut

### Schritt 1: Pflanzen und Bäume
- **Zwei eigene Büsche** (`tools/art_hexenwald.py`, `make_shrub`/`make_broom`, je 3 Varianten + `_stripped` + `_glow`). Beide sind `Bush` in `data/plants.json`, nichts zu pflücken, die Sichel gibt Faser und Stöcke:
  - **Dämmerstrauch** `hex_shrub`: niedriges, dichtes Polster aus blau-schwarzen Blättern, violett im tiefsten Schatten, ein paar blasse Dämmerblätter und violetter Tau.
  - **Besenginster** `witch_broom`: aufrechter Fächer dünner Ruten aus einer Wurzel, sparsame Schuppenblätter, blasse violette Knospen.
- **Wiesenbusch nur noch am Saum:** `PropGenerator._hex_bush`. Ein `bush`, der in den Hexenwald fällt, bleibt nur bei Dämmer unter 0,45 manchmal ein Wiesenbusch, sonst wird er nach Position (ohne Zufallszug) zu Dämmerstrauch (3/5) oder Besenginster (2/5). Gezählt auf der Probefläche: 68 Wiesenbüsche am Rand, 611 eigene.
- **Mehr eigene Kleinpflanzen:** Das Unterholz der Wälder ist dichter (10–17 statt 7–14 Pflanzen, mit Hüten und Kerzen). Streublumen kommen zu zweit oder dritt (50 %). Probefläche: 2833 statt 2493 Pflanzen.
- **Bäume:**
  - Kurze, wandernde Stammadern mit einer Gabel. Auf der Ulme grün, auf dem Bleichbaum violett und hoch oben.
  - Leuchtende Flechtenkrusten (`lichen`) auf der Lichtseite.
  - Pilzkonsolen mit violett atmenden Lamellen auf der Ulme.
  - Hexenhaarspitzen glühen öfter, jede dritte violett.
  - Die Ulme zieht Glühwürmchen an (`fireflies`).
  - Der Bleichbaum hat violettes Licht (`light_color` `#b48ae0`).
- **Atmende Ranken:** `hag_tree_vines.png` hat drei Zeilen: Ranken, Maske, Knospenlicht. Gezeichnet wird mit `hang_vines`, 2–8 Efeuranken je Baum mit Blattpaaren und eingerollter Spitze, manche mit einer Leuchtknospe. `FirTree._make_vines` hängt sie als Kind an die Krone (sie verblassen und fallen mit ihr). `vine_breathe.gdshader` schiebt jede Zeile in ganzen Pixeln. Die Verschiebung wächst zur Spitze hin und folgt einem langsamen Atem, nicht dem Wind. Eine Welle läuft die Ranke hinab. Die Uhr ist `g_wind_clock` (pausiert mit dem Spiel), die Phase hängt vom Standort ab.
- **Knarrender, zuckender Bleichbaum:** `plants.json` `twitch` (`FirTree._twitch`). Alle 9–26 s ruckt er kurz, als bewege sich etwas darin, und knarrt hörbar bis 320 px (`creak_a/b/c`, `tools/audio_hexenwald.py`, Effektlautstärke). Das läuft lokal und rein kosmetisch. `sway` ist jetzt 0,012.

### Schritt 2: Boden
- **Hexen-Waldbett:** Zeile 1 von `forestbed.png` (`tools/art_forestbed.py`, `hex_bed`) mit schwarzviolettem Humus, totem Laub (Wein, Rost, Umbra), schwarzen Wurzeln, grauem Hexenhaarmoos, Flechten und winzigen knochenweißen Pilzen. Bäume der Hexenwälder legen es als Varianten 6–11 (`PropGenerator._witch`, `WorldLevel._add_forest_bed` liest Zeile und Größe aus `variant / 6` und `variant % 6`).
- **Eigene Bodendetails:** `MeadowDetails` 26–29, nämlich Hexenhaarmoos-Polster, totes Laub, ein schwarzer Wurzelbogen und drei Knochenpilzchen. `COUNT` ist jetzt 30, die Wiese wählt weiter nur aus `MEADOW_COUNT` 26, ihre Zufallszüge bleiben gleich. Im Hexenwald ist es halb Gras, halb eigener Boden, auf dem Waldbett nur eigener Boden. Die eigenen Arten werden nur leicht getönt. Dichte `wind.json` 0,55.
- **Bleiche umgestürzte Stämme:** `python3 tools/art_fallen_logs.py bone` erzeugt `fallen_logs_bone{,_glow}.png`, dieselben drei Modelle als Bleichholz mit violetten Rissen, Hexenhaarmoos und violetten Konsolen mit grünem Rand. `FallenLogScatter` legt sie im Hexenwald (Chance x1,25) als Frames 24–47. `FallenLog` wählt Bild und Ernte (`harvest.json` `fallen_bone_log`: Bleichholz).
- **Lichtungen mit Hexenringen:** 15 % der `witch_wood`-Zellen sind eine Lichtung (`_clearing_middle`, reine Funktion der Zelle). Darin liegt ein Ring aus 7–10 Krötenschirmen, Kerzen oder Hüten, oft mit einer Alraune in der Mitte, und Blumen und Farne am Waldrand. Innerhalb von 7,5 Tiles wachsen keine Bäume, Hecken oder Büsche (`_in_clearing` in `_add`).

### Schritt 3: Kleine Bewegung und Licht
- **Sporenwolken:** Krötenschirme stoßen bei Berührung und alle 9–26 s von selbst eine schwere, langsam sinkende Sporenwolke aus (`Flora` `puff_sink`, `puff_idle`).
- **Flackernde Grabkerzen:** Das Licht flackert in kleinen, ungleichen Schritten und taucht ab und zu tiefer ab (`Flora` `flicker`).
- **Fallende Blätter und Asche:** Die vorhandenen Luftpartikel von `WorldWind` (Budget 8) sind im Hexenwald trudelnde tote Blätter aus den Kronen und Ascheflocken mit gelegentlicher violetter Glut.
- **Glühwürmchen in der Dämmerung:** Im Hexenwald fliegen sie auch tagsüber mit 45 % Nachtstärke, in Hexengrün und ab und zu Violett (`Fireflies._night_here`, `WITCH_COLORS`).
- **Violett als zweite Lichtfarbe:** Hexenhut-Licht, Bleichbaum-Licht, Pilzlamellen, Rankenknospen, ein Drittel der Haarspitzen und die Adern der toten Bäume leuchten violett. Grün bleibt bei Kerzen, Ulmenadern und Krötenschirmen.

### Schritt 4: Tiere
- **Krähen in großen Schwärmen:** `wildlife.json` `crow.witch_forest`:
  - 75 % Chunk-Chance, Schwärme von 6–12 Vögeln, gemeinsames Limit 22 im Hexenwald.
  - Beim Spawnen sitzen sie in einer engen Sonnenblumen-Spirale (`spacing` 12 px).
  - Sie halten nur 10 px Abstand (`personal_space`) und ziehen sich ab 40 px zur Schwarmmitte (`flock_pull`).
  - Raben: 45 %, 2–4 Vögel.
  - Bleichbäume bieten 2–5 Äste in einer Zickzack-Reihe (`CorvidPopulation._slot_count`, `_slot`; Wiesenbäume unverändert 1/3). So sitzt ein ganzer Schwarm auf einem toten Baum.
- **Beobachter:** `WildCorvid._observe`, nur Host, nur `witch`. Pro Schwarm sucht sich ein Vogel eine Spielerin, die in 260 px vorbeigeht. Er fliegt ihr in 3–5 Sprüngen voraus, landet 115–170 px vor ihr auf einem Ast (`perch_near`) oder am Boden und schaut ihr zu. Danach fliegt er zum Schwarm zurück und pausiert 40–90 s. Raben tun das seltener. Fluchtregeln gelten weiter.
- **Nachtfalter an den Grabkerzen:** Im Hexenwald fliegen sie ständig (`TinyWildlife._dusk`) und bleiben bei Tagesanbruch. Sie bevorzugen die Flammen der Grabkerzen (Chance 0,9, 3–5 Falter).
- **Kröten:** `TinyWildlife` `toad`. Sie wohnen bei Krötenschirmen (`plants.json` `group: "toad_spots"`), sitzen lange und hüpfen in kurzen Läufen (2–5 Sprünge à 4–9 px, Hüpfbogen 3 px). Kommt jemand nahe, springen sie weg. Ab und zu quaken sie leise (`toad_a/b`). Es gibt drei gedämpfte Färbungen, gezeichnet als Pixel-Maps im Code.
- **Fledermäuse:** `TinyWildlife` `bat`. Sie flattern zwischen den Kronen der Hexenbäume in 26–50 px Höhe mit Flügelschlag und schwachem Bodenschatten. Ab und zu hängen sie kopfüber unter einer Krone (ihre Zeichnung ist dann Kind der `Crown`, schwankt und verblasst mit ihr). Bei Störung fliegen sie los.
- Alles ist host-autoritativ über die vorhandenen zuverlässigen `_act`-Segmente. Es gibt keine neuen Sync-Felder, keine Beute und kein Leuchten an Tieren.

### Prüfung
`tools/test_hexenwald.tscn` prüft zusätzlich:
- eigene Büsche gegen Wiesenbusch, Hexen-Waldbett und eigene Bodendetails in echten Chunks;
- Kröten, Fledermäuse und Falter in echten Chunks;
- bleiche Stämme nur im Hexenwald;
- das `witch`-Flag der Vögel und einen Krähenschwarm von mindestens 8 Vögeln.

Bildprüfung: `tools/preview_daylight.tscn -- --at=800,875 --zoom=2`.

## 3. Offen und Ideen für danach
- **Rabenbaum als Ort:** Ein großer Bleichbaum, an dem sich in der Dämmerung alle Vögel sammeln, mit Kartennamen.
- **Bleiche Eule:** Eigene Federvariante, im Hexenwald auch tagsüber wach.
- **Unterholz:** Schwarze Schnecken und Weberknechte als Varianten der Blätterkrabbler.
- **Krähen und Trugbilder:** Die Vögel könnten auf Halluzinationen reagieren. Mit dem Klarheitstalisman wären sie ruhiger.
- **Eigene Bodenkacheln:** Laub, Moos und Erde direkt im Atlas.
- **Gegnerauswahl der Nacht im Hexenwald:** siehe `docs/hexenwald_konzept.md` Stufe 5.
