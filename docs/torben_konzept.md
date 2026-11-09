# Torben, der Schmied: Einbau-Konzept

Stand: 2026-11-09. Status: **Konzept, nichts gebaut.** Grundlage ist das Dossier `docs/characters/torben.md` (Kanon, wird hier nicht verändert; Abweichungen stehen in Abschnitt 13). Alle Texte in diesem Dokument sind **Platzhalter** für den Dialog-Writer (`docs/prompts/dialogue_writer.md`, nennt Torben schon). Figur, Porträt, Gebäude, Audio und Code entstehen direkt in Claude Code, ohne Subagents.

Vorbild für Aufbau und Tiefe ist `docs/gustav_quest_konzept.md`. Torben ist bewusst **das Spiegelbild von Gustav**: Gustav redet für zwei und wird gerettet; Torben schweigt für drei und rettet sich selbst, nur nicht vor dem, was er nicht greifen kann.

---

## 0. Kurzfassung

| Thema | Entscheidung |
|---|---|
| Rolle | Zweiter Siedler mit Schlüsselrolle: **Eisen**. Erz wird zu Barren, Barren zu Werkzeug und Waffen. Er übernimmt Gustavs Schmiede-Aufträge (`sword_iron`). |
| Fundort | Er hämmert in der alten Zeche (Eingang `old_mine`, Tile 736/736), in einer eigenen **Schmiedehalle hinter einer Eisentür auf Ebene 3** (obere Schächte). Das Hämmern ist der Wegweiser. |
| Quest-Motiv | Ellie klopfte (Kanaldeckel), Gustav klopfte (Wagen), **Torben hämmert**. Sie klopft an seine Tür, er zieht sie am Kragen hinein. |
| Kampf | Ein Riss in der Hallenwand blutet Leere (Spinnen, Listener). Torben schließt ihn mit drei Eisenplatten, Ellie hält ihm den Rücken frei. Er kann Schatten schlagen, aber den Riss nicht: das ist seine Urangst, spielbar. |
| Rückweg | Er geht voran (Umkehr zu Valdric/Gustav, die sie führte oder die Ellie führte), schweigend, und wartet nur, wenn sie zu weit zurückfällt. |
| Gebäude | Neues Teil **SCHMIEDE** (`smithy`, Kategorie HANDWERK), braucht den Bewohner Torben (`needs_resident`, wie die Werkstatt Gustav), größer und heißer als die Werkstatt. |
| Figur | Eigene Ellipsoid-Figur (`tools/art_torben.py`), 8 Richtungen, größer und breiter als Gustav. Erkennungsmerkmal: Vorschlaghammer mit gekerbtem Eschenstiel. Akzent: Glutorange. |
| Porträt | 103×153, gemalte Quelle, auf den Sprites-Look gebacken, sprechend (5 Mundformen), dazu ein Stimmungszustand für den Zorn. |
| Neu für das Spiel | Eisenkette (`iron_ore`, `iron_ingot`, `iron_plate`), Erzadern in der Mine, Werkzeugstufe Eisen, **Man-Handling** als Siedler-Fähigkeit, Regieanweisungen in Dialogzeilen (`act`). |
| Umfang | 11 Schritte (Abschnitt 11), Quest-Dauer etwa 25 bis 30 Minuten, ein Drittel davon Erz sammeln. |

Leitplanken (ponytail): alles datengetrieben und auf vorhandenen Systemen (`TownManager`, `Settler`, `ShopWindow`, `Interiors`, `QuestComponent`, `SpeechPortrait`, `KnightWalkScene` als Vorlage). Neuer Code nur dort, wo es nichts Passendes gibt (Abschnitt 10).

---

## 1. Ausgangslage

**Gebaut und nutzbar:** Siedler-System (Tagesplan, Vertrauen, `produces`, `talk`, `chat`, Barks), `ShopWindow` mit Reitern `craft/order/buy/sell`, `needs_resident` an Bauteilen, `StoryGustav` + `add_story_resident` + `takes_over`, Interiors (Cabin-Kampf zeigt, dass Spinnen in Taschenräumen funktionieren), Mine bis Ebene 5 mit Schmiede-Props (`forge`, `anvil`, `quench` in `assets/mine/props/`), `burn` als Statuseffekt, Chatter zwischen Siedlern (`data/chatter.json`).

**Nicht gebaut (Torben braucht es):**
1. **Erz.** `docs/mine.md` §8 sieht `ore_tier` vor, im Code gibt es nichts davon (Erzadern liefern nirgends `iron_ore`).
2. **Eisen-Items** (Erz, Barren, Platte, Eisenwerkzeuge). Einziges Eisen heute: `sword_iron` (Rezept bei Gustav, mit Void-Splitter).
3. **Eine Schmiede als Gebäude.** Die Werkstatt hat Esse-Optik (`spill.forge`, Funken), ist aber Gustavs Werkbank.
4. **Quest-Ziele in der Mine.** Quest-Tiles sind Weltkoordinaten; die Mine liegt weit außerhalb der Karte. Marker und Distanzzeile taugen dort nicht.
5. Alles Figuren-, Porträt- und Audio-Material von Torben.

**Dossier-Fakten, die das Konzept trägt:** Ex-Minen- und Zeugschmied, stößt dazu, wenn Erz aus den oberen Schächten kommt, Gustav macht Platz für Esse und Amboss; Man-Handler; redet 3 bis 5 Wörter; Urangst Ungreifbares; früher Kriegswerkzeug, jetzt Schutzräume; riecht nach Steinkohle, Horn, Eisenstaub, Flusswasser.

---

## 2. Rolle im Spiel

1. **Stufe Eisen.** Stein/Holz-Werkzeuge (`*_basic`) bleiben die Einstiegsstufe. Eisenwerkzeuge sind Aufträge an Torben (Bestellreiter), damit Vertrauen, Holz, Erz und Wartezeit zählen. Genaue Werte: Balancing offen (Abschnitt 7).
2. **Er nimmt Gustav das Schmieden ab.** Gustavs Werkstatt behält Bretter, Seil, Axt, Sichel, Rute (alles Holz und Faser); `sword_iron` wandert zu Torben. Gustav freut sich darüber (Chatter): er hat die Esse sowieso nur gebaut, weil keiner sonst da war.
3. **Er sichert.** In einem Vorstoß (`alert_on`) geht Torben zum Rand des Lichts und hält ihn wie Valdric, nur körperlich: *„Hinter mich. Alle.“* Reiner Ausdruck wie bei Valdric, keine Spielregel.
4. **Er schiebt Menschen.** Das **Man-Handling** (Abschnitt 9.3) ist seine Markenfähigkeit: kleine Szenen, die ihn lesbar machen, ohne dass er redet.
5. **Später (nicht jetzt):** Eisentor, Eisenlaterne, Riegel für Schutzräume (Vertrauen 60+). Das Dossier nennt „Schutzräume errichten“ als sein tiefstes Bedürfnis; wir lassen dafür nur Platz im Datenformat.

---

## 3. Ingame-Figur

Kein Stand-in: eigene Sheets nach der Pipeline von `tools/art_gustav.py` (Ellipsoid-Renderer von Ellie, gleiche Tinte/Kontur/Körnung). Ein Skript `python3 tools/art_torben.py [kontakt.png | quick out.png]` schreibt `assets/characters/torben.png`, `torben_glow.png` und `data/torben_rig.json`.

### 3.1 Proportion und Silhouette

| Größe | Zielwert (am Kontaktbogen gegen Ellie, Gustav, Valdric prüfen) |
|---|---|
| Frame | 88×96, Füße (44, 80), 8 Zeilen = Sektoren E SE S SW W NW N NE |
| Körperhöhe | etwa 60 px (Ellie ≈ 52, Valdric ≈ 62 mit Helm): **größer als Gustav, kleiner als Valdric mit Helm, aber deutlich breiter als beide** |
| Schultern | ≈ 1,8 × Ellie, fast kein Hals, Nacken wie Taue (flache Ellipsoide) |
| Arme | Unterarme dicker als Ellies Oberschenkel, Hände groß (vier Pixel breit sichtbar) |
| Haltung | leicht nach vorn gebeugt, schwerer Schwerpunkt, **leiser Gang** (Fußaufsatz weich, kein Wippen, wenig Kopfbewegung) |

Lesbarkeit aus 8 Richtungen: breites Dreieck (Schultern, Schürze), darüber ein kleiner dunkler Kopf mit straff gebundenem Haar, **der Hammerstiel über der Schulter als Diagonale**. Das ist sein Erkennungsmerkmal (Regel §3.3 der Design-Doku: ein Erkennungsmerkmal, ein Akzent, alles andere gedämpft).

### 3.2 Bauteile und Farben (Startwerte, vier Stufen dunkel → hell)

| Teil | Ramp |
|---|---|
| Haar und kurzer Bart (rußgeschwärzt, Grau an den Spitzen) | `17121a 2e2630 4a3f48 6e6068` |
| Haut (rußig, rotbraun, Brandnarben heller, Schlackespritzer als 1-px-Punkte) | `4a2a2c 7d4a3f a8715a d09a7c` |
| Schürze: gehärtetes Bullenleder, zwei Lagen, obere dunkler mit verbranntem Rand | `1d130f 3a2418 5f3d28 86593a` |
| Ärmelloses Wollhemd, ungefärbt | `2a2630 514b55 7d767a a89f9c` |
| Hose, Stiefel (Eisenkappe) | `17141c 2d2832 48404a 675d63` |
| Eisen (Zangen, Hammerkopf, Gürtelschnalle) | `16182a 3d4560 72809f b4c0d8` |
| Eschenholz (Stiel, gekerbt, Schlichthammer) | `3a2b26 6e5139 a07c53 cfaa78` |
| **Glut** (nur im Glow-Sheet: glühendes Eisen in der Zange, Hammerkopf nach dem Anwärmen) | `7a1e12 c4461a ff8a2a ffd27a` |

Augen: tief liegend, dunkle Braue davor, kleiner heller Punkt (`24202e`, `5a4a3a`, hell). Kein Violett: Violett gehört Ellie und der Leere.

Ausstattung: Zangen und Lederlappen am Gürtel (ändern sich nicht), kleiner Schlichthammer an der Hüfte, **großer Vorschlaghammer** auf der Schulter (zwei Zustände: geschultert / in beiden Händen), Haar mit Lederband. Leuchtmaske: nur glühendes Eisen (siehe Clips). Alles andere bleibt von der Welt beleuchtet.

### 3.3 Clips (`data/torben_rig.json`)

**MVP** (erste Lieferung, reicht für Siedlerbetrieb und die Quest):

| Clip | Frames / fps | Hinweis |
|---|---|---|
| `idle` | 4 / 4 | Atmung, Hammer geschultert, ab und zu Brauenzug |
| `walk` | 6 / 7 | schwer, leise, Hammer geschultert |
| `work` | 8 / 6, `strike` 4 | großer Schlag auf den Amboss (Blick nach Norden), Ausholen länger als bei Gustav; Glow-Sheet zeigt das glühende Stück |
| `sledge` | 8 / 7, `strike` 4 | Vorschlaghammer in zwei Händen, Schlag auf die Platte am Riss (Kampfszene) |
| `swat` | 5 / 12 | Hammer schlägt waagerecht zur Seite (er wischt Schatten weg) |
| `stand` | 4 / 3 | Arme verschränkt, Blick auf einen Punkt (Wache, Warten) |
| `sit` / `sit_down` | 4 / 3, 6 / 8 | auf Baumstumpf/Bank am Feuer, Hammer zwischen den Knien |

**Zweite Lieferung** (Man-Handling und Details):

| Clip | Frames / fps | Hinweis |
|---|---|---|
| `lift` | 6 / 10 | Rechter Arm schnellt vor, Faust am Kragen, hebt an |
| `carry` | 4 / 6 | geht mit ausgestrecktem Arm, Last hängt (Ellie wird als Sprite darüber geführt, §9.3) |
| `set_down` | 4 / 8 | setzt ab, klopft den Staub von Schulter und Hand |
| `shove` | 5 / 10 | Handfläche gegen Brust, schiebt Gustav oder Valdric |
| `grab_armor` | 6 / 8 | packt Valdrics Harnisch beidseitig, rüttelt (Valdric spielt `stand`) |
| `bellows` | 6 / 5 | zieht den Balg |
| `quench` | 6 / 6 | taucht das Stück ins Fass, Dampf (Partikel) |
| `nod`, `snort` | je 4 / 6 | Kopfnicken, abfälliges Schnauben (Antwort ohne Worte) |
| `knock_wait` | 4 / 4 | steht hinter der Tür, lauscht (wird nur gebraucht, wenn Kameraschnitt hinein kommt) |
| `run` | 6 / 9 | nur für den Notfall (Raid), er läuft selten |

### 3.4 Prüfung der Figur

Kontaktbogen `docs/img/torben_directions.png` (Ellie, Gustav, Valdric, Torben nebeneinander in gleichem Maßstab), Animations-GIF, `tools/test_torben_art.tscn` nach dem Muster von `test_gustav_art.tscn` (Rig-Frames, Füße, Sektoren, Glow nur auf Glutpixeln, Clip-Längen).

---

## 4. Dialogporträt

Verbindlich: `docs/dialogue_art.md` (103×153, Kopf bis Hüfte, Augenhöhe, Dreiviertelblick nach rechts zum Text, Kopf ≈ 45 bis 53 px, Augen ≈ Y 30 bis 40, Schultern ≈ 85 bis 95 % der Breite, Licht links oben, 24 bis 32 Farben). Vergleich mit Ellie auf dem echten Dialoghintergrund vor der Übernahme.

### 4.1 Bild

Pose: **Arme verschränkt**, die Pranken sichtbar an der Hüfte, **der Hammerstiel hinter der Schulter** (zeigt den Erkennungspunkt, verdeckt das Gesicht nicht). Schultern füllen fast die ganze Breite, Schürzenträger kreuzen die Brust, kurzer rußiger Bart, straffes Haar, tief liegende wache Augen unter schweren Brauen, Kiefer mit Muskelzug, ein heller Schlackenspritzer an der Wange. Ruhig, ein bisschen bedrohlich, **nicht grimmig**: das Dossier will „sanfter Beschützer“. Ein Hauch warmes Glutlicht von rechts unten als Kontur (frei wählbar laut Vorgabe), Hauptlicht links oben.

### 4.2 Erzeugung

Wie bei Gustav und Maren: gemalte Quelle, dann Pixelnormalisierung.

1. **Quelle** (Imagegen, hat die Claude-Code-Sitzung nicht; siehe Entscheidung 3, Abschnitt 13): Prompt in §4.4. Ergebnis nach `assets/ui/sources/portrait_torben_imagegen_v1.png` (103×153 oder größer, Alpha).
2. `tools/prepare_torben_portrait.py` (Kopie von `prepare_maren_portrait.py`: Zuschnitt, Nearest-Skalierung auf Höhe 153, Breite 103, harte Transparenz, 30 Farben).
3. `python3 tools/art_torben_portrait.py [vorschau.png]` (nach `art_gustav_portrait.py`): zieht die Farben auf die Sprite-Rampen von §3.2, ändert Pixel für Pixel (Schlackepunkte, Brandnarben), backt **5 Mundformen × Augen offen/zu** nach `assets/ui/portrait_torben_talk.png` (515×306), Standbild `portrait_torben.png`, Beschreibung `data/torben_portrait.json`.
4. Eintrag in `DialogueBox.LATE_PORTRAITS` und `TALKING_PORTRAITS` (`"TORBEN"`), Test nach `tools/test_gustav_portrait.tscn`.

### 4.3 Besonderheiten bei Torben

- **Er spricht kaum.** Die Mundformen sind trotzdem nötig (Ein-Wort-Zeilen), aber bei ihm laufen sie **kürzer und schwerer**: Halten 0,10 s statt 0,07 s (`viseme_hold` in der JSON), Blinzeln seltener (4,6 s).
- **Zusätzliche Zeile im Sheet: `grim`** (Brauen tief, Zähne sichtbar, Nüstern gebläht) für den Riss und seine Zorn-Zeilen, **`soft`** (Mundwinkel eine Spur oben, Augen eine Spur schmaler) für Vertrauens-Zeilen ab 60. `rows` bleibt Datenfeld der JSON: `["open","closed","grim","soft"]`; die Zeile wählt die Dialogzeile über das vorhandene `mood`-Metafeld. Das ist die einzige Erweiterung von `SpeechPortrait` (Reihe nach Name wählen), kleiner Eingriff.
- **Regieanweisungen.** Das Dossier schreibt seine Szenen als „(packt Ellie am Gürtel …) … Scherben. Pass auf.“ Dafür bekommt eine Dialogzeile ein optionales Feld **`act`**: ein gedämpfter Zeilenkopf in Klammern, sofort sichtbar (nicht getippt), der gesprochene Text erst danach. Ohne `act` bleibt alles wie bisher. Betrifft `DialogueBox` (Anzeige) und die Text-Paginierung (der Kopf zählt als eine Zeile).
- **Unbekannt-Filter** wird nicht gebraucht: Ellie kennt ihn nicht, aber sie sieht ihn ja (Sprecher beim ersten Mal „FREMDER SCHMIED“? Entscheidung offen, Abschnitt 13; Standard: Name TORBEN sofort, weil Ellie ihn über Valdric/Gustav kennt).

### 4.4 Prompt für die Quelle (Entwurf, an das Gustav/Ritter-Muster angelehnt)

Ein einzelnes transparentes Pixel-Art-Dialogporträt des Schmieds Torben, Anfang bis Mitte 40, bärenhafter Koloss. Ellies grobe Pixelcluster und Kopf-bis-Hüfte-Ausschnitt als Maßreferenz, Gustavs Porträt als Stilreferenz für die Tonwerte. Dreiviertelansicht nach rechts auf Augenhöhe. Sehr breite Schultern füllen fast die Bildbreite, kaum Hals, Nacken wie gespannte Taue. Kurzer rußgeschwärzter Bart, dunkle buschige Brauen über tief liegenden wachen braunen Augen, straff nach hinten gebundenes Haar mit Lederband, kleine Brandnarben und ein heller Schlackenspritzer auf der Wange. Schwere zweilagige Schürze aus gehärtetem dunklem Bullenleder mit gekreuzten Trägern über einem ärmellosen ungefärbten Wollhemd, Unterarme voller Brandnarben, die Arme vor der Brust verschränkt, ein Vorschlaghammer mit gekerbtem Eschenstiel lehnt hinter der rechten Schulter. Ruhiger, fester, beschützender Blick, Kiefer entspannt aber bereit. Hauptlicht von links oben, schwacher warmer Glutschein von rechts unten. Wie auf 103×153 Pixeln handgezeichnet, deutlich eckige Pixelstufen, etwa 30 Farben, 3 bis 4 flache Töne je Material, keine Glättung oder Verläufe. Kein Hintergrund, kein Text, kein Rahmen, kein Ganzkörperbild, keine reine Silhouette.

---

## 5. Stimme, Ton und „Sprechen ohne Worte“

Torben ersetzt Worte durch Handlung. Das spiegelt sich in drei Schichten:

1. **Zeilen:** höchstens 3 bis 5 Wörter, oft nur `act` plus ein Wort. Urteile: *Schrott. Hält. Kalt. Lass.* Die längste Rede im ganzen Spiel (Vertrauen 100, §9.4) hat etwa 25 Wörter.
2. **Sprechblasen und Barks** (`chat`): dieselben Zeilen, auch als reine Gesten (*nickt*, *schnaubt*) in der `SpeechBox`, gedämpft gezeichnet.
3. **Ton** (`python3 tools/audio_torben.py`, synthetisierte Platzhalter wie überall):

| Klang | Zweck |
|---|---|
| Schwerer Hammerschlag auf Amboss (3 Varianten, tiefer und länger nachklingend als Gustavs `hammer_a-c`, hellerer Gegenton) | `work`, Siedlerarbeit, Wegweiser in der Mine |
| Vorschlag auf Eisenplatte | Riss-Szene |
| Balg (atmen), Löschwasser-Zischen, Esse-Knistern (Loop), Zange auf Eisen | Schmiede, Silhouette |
| Grollen, Schnauben, Knurren (3 tiefe Formantklänge, keine Sprache) | Zeilen-Antworten, `nod`/`snort` |
| Schwere, leise Schritte | Siedlerfuß |
| Tür-Riegel schwer, Eisentür | Quest |

**Das Hämmern als Wegweiser:** ein Muster aus drei Schlägen (kurz-kurz-lang), Pause, wiederholt; auf Ebene 1 leise und dumpf (`wiederholter Ton durch den Fels`), Ebene 2 lauter, Ebene 3 positional und klar. Dieselbe Idee wie Gustavs Klopfen, nur schwerer.

---

## 6. Die Schmiede (Gebäude in der Stadt)

Neues Teil `smithy` in `data/town.json`, Kategorie `craft`, Pipeline wie Werkstatt und Vorratslager (`tools/art_town.py` bekommt eine Funktion, danach `art_town_decor.py`). Alles ein echtes Ellipsoid-Modell in den Farben der renovierten Hütte, **aber dunkler, rußiger, schwerer**: das Gegenstück zu Gustavs freundlicher Holzwerkstatt.

### 6.1 Aussehen

Offener Schmiedeschuppen mit gemauerter Esse an der Rückwand und dickem Schornstein, Schieferdach (die Schindelpass `hut_lib.roof_pass` mit der Schieferfamilie), grobe Holzpfosten, zur Straße offen. Davor und darunter: **Amboss auf einem Eichenblock** (große Seitenfläche, sichtbare Kerben), Löschfass mit Wasser, Blasebalg an der Esse, Zangen- und Hammerwand, Kohlekiste, Haufen Schlacke und Alteisen an der Seite, an der Wand zwei fertige Eisenplatten als Muster. Dazu ein schwerer, rostiger Tavernenschild-Anleger mit Hufeisen (`parts`, Wind: schwingt kaum).

Maße (Startwerte): Fuß 112×44 px (Werkstatt 96×40), Bild 160×120, `feet` 104, `snap` 8, `pad: true` (der Boden unter großen Teilen wird festgetreten; hier mit **Aschekreis** um den Amboss, eigene Padtextur), `front` [100, 34] (Türzone: die Arbeitsfläche). Der Weg zur Schmiede entsteht automatisch (`paths: true`).

### 6.1a Gebaut (2026-11-09): die Form

Statt eines Holzschuppens eine **Steinschmiede** (`python3 tools/art_smithy.py [vorschau.png] [--json]`, Test `tools/test_smithy.tscn`, Vorschau im Spiel `preview_town.tscn -- --smithy [--night] [--aged]`): eine geschlossene Steinhalle mit steilem **Schiefergiebel zur Straße** (alle anderen Bauten haben Pultdächer), Rundbogentor mit flach an die Wand geklappten Torflügeln, Amboss-und-Hammer-Emblem aus Stahl im Giebel; rechts die **Esse**: ein breiter Herdblock mit Steinbogen und flackernder Glut (sechs Flackerbilder als animierte Glow-Leiste), eine Haube, die in einen **runden, sich verjüngenden Schornsteinturm** übergeht, der höher ist als alles in der Stadt. Davor das Pflaster des Schmiedeplatzes mit Amboss auf Eichenstumpf, Löschtrog, Wasserfass und Blasebalg am Herd; links Erz, Kohle und Eisenbarren. Teile: zwei Laternen am Tor, ein Amboss-Schild, der Wimpel der Stadt; Ruß am Stein, Rußboden (`smithy_pad`), Lichtpools (Esse, Tor, Laternen), Verschleiß (Ruß, Kohle und Erz, Schlackehalde, Moos nach 5 und 11 Tagen, Spinnweben bei Verwaisung).

### 6.2 Daten (Entwurf)

```
"smithy": {
  "name": "SCHMIEDE", "category": "craft", "texture": "smithy",
  "needs_resident": "torben", "level": 2,
  "foot": [112, 44], "front": [100, 34], "snap": 8, "pad": true, "paths": true,
  "cost": {"wood": 16, "stone": 30, "plank": 6, "iron_ore": 8},
  "build_seconds": 40.0, "reach": 64.0, "worth": 18, "role": "smith",
  "glow": true, "light": {"color": "ff7a2a", "radius": 72, "energy": 1.0, "at": [...], "flicker": 0.35},
  "smoke": {"at": [...]}, "sparks": {"at": [...], "color": "ffb25a"},
  "spill": {"texture": "smithy_spill", "forge": true, "base": 0.9},
  "info": "ESSE, AMBOSS UND EISEN"
}
```

- **Warum `plank` und `iron_ore` in den Kosten:** Gustavs Bretter und der Fund aus der Mine sind Teil der Geschichte (Gustav „macht Platz für Esse und Amboss“, der Erzvorrat ist die Eintrittskarte). Die 8 Erz liegen genau in der Menge, die die Quest ohnehin abbauen lässt (Abschnitt 8).
- **Licht:** wärmer und stärker als die Werkstatt (`ff9a3a`, 60, 0,8). Fällt auf Glut (`forge`-Regel des Spill: „sinkt ohne Siedler auf Glut“) und wird nachts Nachtlichtquelle (Lichtkreis der Stadt).
- **Lebendigkeit** (alles Daten): `wear` (Ruß in drei Stufen nach 1, 3, 6 Tagen, **Schlackehalde, die mit den Tagen wächst**), `parts` (Balg pumpt, wenn er arbeitet; Zangen schwingen), `perches` für Krähen auf First und Schornstein, **Dampfwolke am Löschfass** (Partikel, nur wenn Torben `quench` spielt), `shutters` nicht nötig.
- **Konflikt mit Gustavs Werkstatt:** keiner. Die Werkstatt behält ihre Esse als Zierde, das Teil `workshop` bleibt unverändert.

### 6.3 Schmiedefenster

`data/shops.json` Eintrag `torben_forge` (Stufe `ShopWindow`/`BoardWindow` unverändert): Titel **ESSE**, `npc: "torben"`, `role: "smith"`, Reiter `ORDER` (Bestellungen), `BUY` (Barren, Nägel), `SELL` (Erz, Schrott). Kein `craft`-Reiter („Das kann ich allein“ ist nicht seine Haltung), außer **Platten und Nägel** als Selbstbau am Amboss (siehe 7.2, kurzer Balken, Torben schaut zu). Seine Zeilen (`lines`) sind Ein-Wort-Antworten:

| Moment | Platzhalter |
|---|---|
| open | *„Was.“* / *„Hm.“* |
| craft | *(nickt)* |
| order | *„Dauert.“* |
| collect | *„Hält.“* |
| buy / sell | *„Gut.“* / *„Schrott.“* (bei billigem Zeug) |
| no_trust | *(schüttelt den Kopf)* |

---

## 7. Erz und Eisen

### 7.1 Gegenstände (`data/items.json`, Icons nach Regel §4 der Design-Doku, 16×16)

| Item | Art | Herkunft |
|---|---|---|
| `iron_ore` „Eisenerz“ | Material | Erzadern in Mine Zone 1 (Ebenen 1 bis 5), ochre-rostiges Gestein mit violettem Aderrand |
| `iron_ingot` „Eisenbarren“ | Material | Torben schmilzt: **2 Erz + 1 Holz → 1 Barren pro Spielstunde** (`produces`, wie Gustavs Bretter; Holz konkurriert mit Brettern) |
| `iron_plate` „Eisenplatte“ | Material | 2 Barren am Amboss (Selbstbau am Amboss oder Bestellung) |
| `axe_iron`, `pickaxe_iron`, `sickle_iron` | Werkzeug | Bestellungen |
| `sword_iron` (vorhanden) | Waffe | wechselt von Gustav zu Torben (`npc`), bleibt `by: "npc"` |

Nur ein neues Basis-Item pro Zeile des Dossiers (Erz → Barren → Platte); keine Kohle, keine Legierungen (das nennt das Dossier nur als Fischöl-Tausch mit Maren, Fischsystem-Konzept, später).

### 7.2 Rezepte (`data/recipes.json`, Zahlen sind Startwerte, Balancing offen)

| Rezept | Zutaten | `by` | Arbeit | Vertrauen |
|---|---|---|---|---|
| `iron_ingot` | 2 Erz, 1 Holz | auto (`produces`) | 1 Spielstunde | 0 |
| `iron_plate` | 2 Barren | self (Amboss) | 3 s | 0 |
| `nails` (optional) | 1 Barren | self | 2 s | 0 |
| `pickaxe_iron` | 3 Barren, 1 Brett | npc | 60 s | 0 |
| `axe_iron` | 3 Barren, 1 Brett | npc | 60 s | 10 |
| `sickle_iron` | 2 Barren, 1 Seil | npc | 45 s | 20 |
| `sword_iron` | wie bisher (Schwert, Bretter, Stein, Void-Splitter) + 2 Barren | npc `torben` | 100 s | 20 |

**Werkzeugstufe (Vorschlag, Entscheidung 5):** Werkzeuge bekommen ein Feld `tier` (Stein 1, Eisen 2). Die Mine spricht von `ore_tier` je Zone; Zone 1 hat Tier 1 (geht mit Stein), tiefer braucht die Eisenhacke. Das gibt den Eisenwerkzeugen einen echten Zweck ohne neues System. Nichts davon ist Pflicht für den Einbau; ohne Stufen sind Eisenwerkzeuge einfach stärker (mehr Reichweite/Schaden, haltbarer wäre Haltbarkeit, die es nicht gibt).

### 7.3 Erzadern in der Mine

Eigene Fels-Variante in `MineRocks` mit sichtbarer Ader, eigener Ressourcentabelle in `data/mine.json` (`rocks.ore`: Chance je Zone, Menge 1 bis 2 je Treffer, `ore_tier`, `regrow_days` wie Felsen). Sie nutzen die vorhandenen Fels-Stufen (ganz, angeschlagen, klein, Schutt) und das Zustandsformat (`mine` im Savegame). Art: `tools/art_mine_props.py` (Ader aus 3 bis 5 Splittern in der Felsfläche, kein Leuchten außer sehr schwachem violettem Rand). Erste Erzmenge der Quest: ≥ 8 auf Ebenen 1 bis 3, Spawn-Garantie je Ebene: **mindestens 6 Adern**, damit die Quest nicht an Zufall hängt.

---

## 8. Die Quest-Kette

Drei Quests nach dem Muster von `town_start → gustav_rescue → town_workshop`. Alle Szenen **Host/Solo** wie die übrigen Story-Szenen, Torben gehört der Stadt (`residents`), nicht einer Spielerin.

```
town_workshop (Gustav, Spitzhacke)  ── next ──▶  town_ore    DAS ALTE ERZ
                                                    │ next
                                                    ▼
                                           torben_forge  DAS HÄMMERN IN DER TIEFE
                                                    │ next
                                                    ▼
                                           town_smithy   DIE SCHMIEDE
```

### 8.1 Auslöser

`town_workshop` endet mit der Spitzhacke. Neuer Schluss-Dialog (Gustav, beim Herstellen): *„Stein bricht Stein. Für mehr brauch ich Eisen. Und jemanden, der es versteht.“* Das ist der Anker und startet `town_ore`. Alte Spielstände: `QuestComponent._migrate_*` wie bei Gustav (wer die Werkstatt schon hat und die Spitzhacke gebaut hat, bekommt `town_ore` beim Laden).

### 8.2 `town_ore` „DAS ALTE ERZ“

| # | Schritt | Typ | Inhalt |
|---|---|---|---|
| 1 | `ore_valdric` SPRICH MIT VALDRIC | `reach` actor knight | Er kennt den Zechenweg: *„Die alte Zeche. Südwestlich. Wer dort arbeitete, hat nicht alles mitgenommen.“* Er gibt keine Waffe. Tutorialkarte für die Mine (`hint: "mine"`: Lampen, Aufzug, Erzadern). |
| 2 | `ore_gate` ZUR ALTEN ZECHE | `reach` Tile (736, 736), radius 8 | Der Eingang `MineEntrance` steht schon. |
| 3 | `ore_mine` EISENERZ ABBAUEN | `tasks` | Aufgabe `item` 8 `iron_ore` (Erzadern Ebenen 1 bis 3), Aufgabe `flag` `mine_depth_3` „TIEFER STEIGEN“ (setzt `MineManager`, wenn sie Ebene 3 betritt). Reihenfolge frei. |
| 4 | `hear_hammer` HÖRST DU DAS? | `flag` `hammer_heard` | Auf Ebene 2 setzt eine Auslöse-Zone (Ebene 2, Stationsnähe) eine Barkzeile (`hammer_bark`: *„Metall. Jemand schlägt Metall.“*) und das **Hämmern beginnt** (positionales Ambient, §5). |
| 5 | `follow_hammer` FOLGE DEM HÄMMERN | `flag` `torben_door` | Kein Marker (Tile außerhalb der Karte). `QuestVine` zeigt statt Distanz nur den Text (`"search": 0`, `"hide_distance": true`). Der Weg läuft nur über den Klang; Ebene 3 hat die Tür an einem festen, vom Seed bestimmten Sackgassen-Ende (§10.2). |

### 8.3 `torben_forge` „DAS HÄMMERN IN DER TIEFE“

| # | Schritt | Inhalt |
|---|---|---|
| 1 | `knock` KLOPFE AN | Vor der Eisentür (`Doorway` zum Taschenraum `torben_forge`, `locked`). E: Ellie klopft dreimal, Pause. **Das Hämmern bricht ab.** Stille, ein schwerer Riegel, die Tür springt auf, **eine Pranke packt sie am Kragen und zieht sie hinein**, die Tür schlägt zu (erstes Man-Handling, Szene). Zeile: *(schnauft)* „Still.“ |
| 2 | `see_crack` SIEH DICH UM | Die Halle: Esse, Amboss, Fässer, Pritsche, Haufen Eisenplatten und, in der Rückwand, **der Riss**, dunkel, magentafarben pulsierend, aus ihm kriecht Schattenbefall. Torben steht davor und schlägt eine Platte in den Spalt, die Platte wird schwarz und zerbröselt. Er hat schon zwei Platten verloren. (Ellie, innerer Dialog `forge_a`.) |
| 3 | `seal_crack` SCHÜTZE TORBEN | **Kampf**, drei Wellen (siehe 8.4), jede endet, wenn er eine neue Platte setzt. Danach ist der Riss zu (Glühen erlischt, die Platten bleiben als Narbe in der Wand). |
| 4 | `torben_meet` SPRICH MIT TORBEN | Dialog `torben_meet`: Ellie stellt sich vor und erwähnt Valdric und Gustav. Ein Grollen. *(wiegt den Hammer)* „Wo.“ — „Licht. Eine Stadt.“ — *(nickt)* „Hält.“ Flag `torben_met`. Er packt Hammer, Zangen und den kleinen Hammer ein (Amboss bleibt). |
| 5 | `follow_torben` FOLGE TORBEN | Er geht voran (Aufzug zur Oberfläche, dann der Weg zur Stadt), nicht Ellie führt ihn. Flag `torben_arrived` am Feuer (siehe 8.5). |

### 8.4 Der Kampf am Riss (`TorbenForgeScene`)

- **Ziel:** keine Gruppe schlagen, sondern **Zeit kaufen**. Torben braucht pro Platte rund 14 s ungestörtes Hämmern (`sledge`). Er steht vor dem Riss, Ellie davor auf der Fläche der Halle.
- **Wellen:** 1: zwei Schattenspinnen; 2: Spinne + Listener (Schuss! Torben kann Ellie nicht retten, wenn sie nicht ausweicht); 3: drei Spinnen und ein Listener. Standardwerte der Mine für Zone 1 (`EnemyScaling`); nichts gewürfelt, jede Welle steht in der Szene.
- **Torben im Kampf:** Gegner, die ihn erreichen, bekommen einen `swat` (Rückstoß, kein Kill); er ist unverwundbar (`HealthComponent.floor_value`, wie Gustav in der Eskorte) und nimmt die Zeit nur durch eine Pause von 2 s pro Treffer (`hurt`-Schleife). Er ist also schutzbedürftig, aber kein Eskortenballast: sein Hammer macht ihn zur Barriere im Raum.
- **Der Riss:** eigener Prop (`VoidCrack`, Magentarissnetz mit schwachem Puls; nach jeder Platte kleiner), speit **keinen** unendlichen Spawn, sondern ruft die drei Wellen; wenn Ellie stirbt, setzt die Szene nach der Rückkehr neu an (`resume_story`).
- **Co-op:** weitere Spieler dürfen dazukommen und mitkämpfen (die Szene ist Host-gesteuert; wie bei der Spinnen-Rettung zählt nur Host/Solo für den Questfortschritt).
- **Der Moment:** nach der dritten Platte ein langes Schweigen. Er legt den Hammer ab, sieht sie an, nickt langsam. **Das ist sein „Danke“**; kein Text.

### 8.5 Rückweg, Begrüßung, Einzug (`town_smithy` „DIE SCHMIEDE“)

**Rückweg** (`TorbenLeadScene`, Vorlage `KnightWalkScene`): Torben geht voran, Aufzug und Weg nutzen den normalen Navi (`EnemyNavigation`-Läufer), er blickt alle 12 s zurück und **wartet nicht** (er geht ruhig weiter), bleibt aber stehen, wenn sie 150 px zurückfällt. Barks aus `torben_walk` (Gesten: *nickt*, *schnaubt*). Am Feuer: `TorbenWelcomeScene` (siehe unten).

**Die Begrüßung** (`TorbenWelcomeScene`, Vorlage `GustavWelcomeScene`, nach dem Voice-Check des Dossiers): Valdric steht am Feuer. Torben packt Valdric an den Harnischrändern und dreht ihn um, rüttelt, *„Niete locker. Steh still.“*, schlägt mit dem Schlichthammer zwei Schläge. Gustav kommt dazu und redet; Torben schiebt ihn mit der flachen Hand beiseite. Dann sieht er Gustavs Werkstatt, geht hin, sieht die Esse, *„Zu klein.“* Gustav: lacht, räumt gleich einen Platz frei. Flag `torben_joined`, `add_story_resident("torben")` (Siedler `takes_over: "story_torben"`).

**`town_smithy` „DIE SCHMIEDE“:**

| # | Schritt | Inhalt |
|---|---|---|
| 1 | `sm_gather` MATERIAL FÜR DIE SCHMIEDE | `tasks` `stock`: 16 Holz, 30 Stein, 6 Bretter (Gustav!), 8 Eisenerz (liegen großteils schon im Lager). |
| 2 | `sm_build` BAUE DIE SCHMIEDE | Flag `built_smithy`, `hint: "build"`. Gustav und Valdric helfen (zählen als Helfer). Torben schaut zu und schlägt zum Schluss den ersten Nagel selbst ein. |
| 3 | `sm_movein` SPRICH MIT TORBEN | Er zieht ein (`arrive.needs: smithy`), erste Esse brennt, Banner „TORBEN ZIEHT EIN“ (vorhanden). Gustav übergibt seine Zeilen an ihn. |
| 4 | `sm_first` LASS TORBEN ETWAS SCHMIEDEN | Flag `ordered_iron_pickaxe` (Bestellreiter), `hint: "order"`. Abholen: *„Hält.“* |

Nach dem Ende gilt Torben als normaler Siedler. Dev-Sprung analog `GUSTAV GERETTET`: ENTWICKLER → STORY-SPRUNG → **SCHMIEDE FERTIG**.

### 8.6 Texte (nur Platzhalter, in `data/dialogue.json`; Ton nach Dossier §6)

`town_ore_*` (Valdric, Gustav), `hammer_bark`, `forge_a`, `torben_door`, `torben_meet`, `torben_walk_a..c`, `torben_welcome_a..d`, `sm_gather`..`sm_first`, `torben_talk_a..c`, `chat`-Pools. Ellie spricht mehr als Torben, **die Regel „3 bis 5 Wörter“ gilt für Torben-Zeilen, nicht für Ellies Antworten**. Der Dialog-Writer überschreibt sie später.

---

## 9. Torben als Bewohner

### 9.1 Siedlereintrag (Entwurf `data/settlers.json`)

```
"torben": {
  "name": "TORBEN", "title": "SCHMIED", "art": "torben",
  "takes_over": "story_torben", "role": "smith", "home": "smithy",
  "arrive": {"needs": "smithy", "delay": 0.0, "story": "torben_joined"},
  "spots": {
    "work":   {"of": "home", "at": [..], "face": [0, -1], "clip": "work", "sound": "anvil", "strike": 4},
    "bellows": {"of": "home", "at": [..], "face": [0, -1], "clip": "bellows"},
    "quench":  {"of": "home", "at": [..], "face": [-1, 0], "clip": "quench"},
    "fire":   {"of": "center", "at": [..], "face": [1, 0], "clip": "stand"},
    "watch":  {"of": "home", "at": [..], "clip": "stand"},
    "rest":   {"of": "home", "at": [..]}
  },
  "schedule": [
    [0.24, 0.29, "bellows"], [0.29, 0.54, "work"], [0.54, 0.56, "quench"],
    [0.56, 0.62, "fire"], [0.62, 0.78, "work"], [0.78, 0.80, "quench"],
    [0.80, 0.88, "fire"], [0.88, 0.24, "rest"]
  ],
  "produces": {"in": {"iron_ore": 2, "wood": 1}, "out": {"iron_ingot": 1}},
  "talk": [{"trust": 0, "dialogue": "torben_talk_a"}, {"trust": 30, "dialogue": "torben_talk_b"}, {"trust": 60, "dialogue": "torben_talk_c"}],
  "shop": "torben_forge"
}
```

Er steht früher auf als Gustav (zündet vor Sonnenaufgang die Esse, das Schmiedelicht steigt dann vom Glühen auf Normal) und isst nicht, er **steht** am Feuer (`stand`, Arme verschränkt, nur bei `fire`; setzt sich erst, wenn jemand ihn bittet: Vertrauen 30 gibt ihm `sit` am Stumpf neben Valdric).

### 9.2 Vertrauen und Zeilen

- `chat` nach dem Muster Valdrics (`quest`, `spot`, `night`, `any`), Zeilen 1 bis 5 Wörter, 30 % sind reine Gesten (*(nickt)*).
- Vertrauen 0 bis 29: Einwort-Antworten und Gesten. 30: kleine Gabe (er schärft ihr Schwert unaufgefordert, einmal: `sword_basic` +? nur kosmetisch **oder** ein Barren, Entscheidung offen). 60: er erzählt von den Toren (Dossier §5, die längste Rede, `soft`-Stimmung); schaltet im Datenformat `iron_gate`/„Schutzräume“ als *später* markiert. 100: Hammer-Geste, er lässt sie den Schlichthammer halten.

### 9.3 Man-Handling (Signatur)

**Das ist kein Kampfsystem, sondern eine kleine Szene als Fähigkeit des Siedlers.**

| Auslöser | Ablauf |
|---|---|
| Spielerin steht in der **Funkenzone** des Ambosses (28 px Radius um `work`-Spot, solange Torben arbeitet und die Esse brennt) | Torben unterbricht den Schlag, geht hin (2 s), `lift`: Faust am Kragen, **Ellie wird 10 px angehoben** (ihr vorhandener Gehzyklus strampelt in der Luft, leichte `skew`-Neigung), `carry` zwei Schritte, `set_down` auf die **Kiste** (Spot `crate`, 2 m zurück), Zeile: *(setzt sie ab)* „Zu heiß.“ Ellie: ein Protest-Bark (*„Hey! Ich habe Beine, Torben!“*). |
| **Pro Spieler einmal je Spieltag**, nicht während Quest, Kampf, Bau, Karte, Dialog | `ManHandle`-Cooldown im Host (`TownManager`, pure Zustandszahl). Ohne Cooldown würde er sie bei jedem Spaziergang hochheben. |
| Gustav steht im Weg (Wegesperre im Chatter-System) | `shove`: Handfläche an die Brust, Gustav rutscht zwei Schritte und redet weiter. |
| Valdric am Feuer, Stufe Vertrauen ≥ 30 | `grab_armor` (Zufall 1 × je Spieltag), Valdric schmunzelt. |

Die Funkenzone selbst ist harmlos (kein Schaden). Sie hat **eine** mechanische Folge: wer trotz allem darin stehen bleibt, während er nicht greifen kann (Torben schläft/Pause), bekommt den vorhandenen `burn` mit Funkenbild (kurz, schwach). So hat die Warnung ein Gewicht, und es ist ein Hinweis auf die Gefahr der Esse.

Ellie-Seite: **kein neues Sheet** (MVP). Zweite Stufe optional: ein gebackenes `player_lifted.png` (hängt am Kragen, 8 Richtungen), falls der Gehzyklus in der Luft nicht überzeugt.

### 9.4 Beziehungen (Chatter, `data/chatter.json`, `TownManager.event`)

| Mit | Beispiel |
|---|---|
| Gustav | Gustav redet über die Dachbalken, Torben schiebt ihn zur Seite; Gustav redet unbeirrt weiter (Chatter-Paar, kurzer Dialog: Torben nur Geste). |
| Valdric | Rüttelt am Harnisch. Ohne Worte. Valdric: „Lass ihn.“ |
| Maren (wenn aktiv) | Zwei Stunden am Ufer, Schweigen; Zeilen: *(reicht Haken)*, *(nickt)*. Maren bringt Fischöl, Torben schmiedet Reusenbeschläge: Eintrag in ihrem Handel, aber erst, wenn Maren `enabled` ist. |

### 9.5 Raid

`alert_on`: Torben geht zum Rand des Lichts, `stand`, Hammer in beiden Händen (`watch`). Bark *„Hinter mich. Alle.“*, nur Ausdruck (Valdric-Regel: nichts wird beeinflusst). Seine Angst vor dem Ungreifbaren zeigt sich in der **Nebelnacht** (`fog`-Spezialnacht): er steht dann am Schmiedefeuer und schlägt auf nichts, die Bark wird knurrig (*„Nichts zu fassen.“*).

---

## 10. Technische Umsetzung

### 10.1 Datenänderungen (alles Daten, wie bei Gustav)

| Datei | Änderung |
|---|---|
| `data/items.json` | `iron_ore`, `iron_ingot`, `iron_plate`, `nails` (opt.), `axe_iron`, `pickaxe_iron`, `sickle_iron` (+ Icons) |
| `data/recipes.json` | Rezepte aus 7.2; `sword_iron` `npc: "torben"`, Zutatenliste + 2 Barren |
| `data/shops.json` | `torben_forge`; `gustav_bench` verliert die Schmiede-Info („GUSTAV SCHMIEDET“) |
| `data/town.json` | Teil `smithy`; Kosten und Lichtradius wie 6.2 |
| `data/settlers.json` | Eintrag `torben` |
| `data/quests.json` | `town_ore`, `torben_forge`, `town_smithy`; `town_workshop` bekommt `"next": "town_ore"` |
| `data/dialogue.json` | Platzhalterzeilen aus 8.6 (Zeilenfeld `act` neu) |
| `data/mine.json` | `rocks.ore`, `story_rooms` (Ebene 3, Raum `torben_forge`) |
| `data/ground.json` | optional: nichts (die Mine hängt an `mines`) |
| `data/torben_rig.json`, `data/torben_portrait.json` | von den Skripten geschrieben |

### 10.2 Der Taschenraum `torben_forge`

**Empfehlung:** Interior (`data/interiors.json`, wie der Holzfällerhütten-Innenraum), betreten über eine **Eisentür am Ende eines Seitengangs der Ebene 3**: ein Prop `MineDoor` (eine Doorway, die ein Mine-Prop ist). Vorteile gegen einen generierten Raum: handgebaute Kampffläche, fester Kameraausschnitt, Riss und Amboss exakt platziert, kein Generatoreingriff. Spinnen können in Taschenräumen jagen (`WorldLevel.navigation_floor` ist dort wahr; Cabin-Kampf zeigt das).

- **Risiko (zuerst klären, Schritt 1):** `Interiors` kennt Eingänge der Oberwelt (`register_entrance`); eine Tür *in einer Mine-Ebene* und der Rückweg dorthin sind neu. `Interiors.outer(tree, pos)`, Streaming, `DayNight`-Tönung (Mine immer Nacht, Interior eigene Tönung) und Rückkehr an die Mine-Position müssen getestet werden. **Plan B:** ein generierter Raum `torben_forge` am festen Ort des Seeds (`mine.json` `story_rooms`) über `MineRooms`, ähnlich `_forge()`, mit sichtbarer Eisentür als Prop und Kameralimits der Szene.
- **Zugang:** Tür `locked` bis das Flag `torben_door` (Schritt 5 der `town_ore`) gesetzt ist; der Ort ist deterministisch (Seed): das Ende des längsten Sackgangs von Ebene 3 mit mindestens 20 Tiles Abstand zu Auf- und Abgang. Test über 200 Seeds (wie die übrigen Mine-Tests).
- **Hämmern als Quelle:** ein Ton-Prop an der Tür (`MineSound`) mit Reichweite, bei Ebene 2 (Station) leise vorab, nach dem Flag aus; auf Ebene 1 gar nichts.

### 10.3 Neue Code-Bausteine (minimal)

| Baustein | Zweck | Vorlage |
|---|---|---|
| `StoryTorben` (`src/entities/npcs/story_torben.gd`) | unverwundbarer Questakteur, Clips, Tür, Gehen | `story_gustav.gd` |
| `TorbenForgeScene` | Tür, Riss, drei Wellen, Platten | `cabin_spider_scene.gd`, `gustav_rescue_scene.gd` |
| `TorbenLeadScene` | Führung zur Stadt | `knight_walk_scene.gd` |
| `TorbenWelcomeScene` | Begrüßung, Harnisch, Gustav | `gustav_welcome_scene.gd` |
| `VoidCrack` (Prop) | Riss mit Puls, 3 Stufen | `AmbushEyes`/Mine-Void-Pods |
| `MineDoor` (Prop) | Eisentür als Doorway | `Doorway`, `MineStairs` |
| `ManHandle` (in `Settler`, Spot-Erweiterung) | Funkenzone, Hochheben, Cooldown | `RestComponent`-Muster, `Player.auto_walk` |
| `act`-Feld in `DialogueBox` | Regieanweisung | bestehende Zeilen-Metadaten |
| `SpeechPortrait`: Zeile nach `mood` | `grim`/`soft` | Ellie-`mood` |
| `MineRocks`: Erzader | Erzvariante, Tabelle | bestehende `Rock`-Stufen |
| `QuestComponent`: `hide_distance`, `hammer_heard`/`mine_depth_3` aus `MineManager` | Quest in der Mine ohne Marker | `actor`/`search`-Schritte |

Nicht neu: Siedler-Plan, Shop, Rezept-Ordering, Lichter, Rauch, Funken, Spuren, Chatter, Bauen (alles Daten).

### 10.4 Wiederaufnahme und Migration

`resume_story` setzt nach Speicherstand den Stand wieder: Tür offen/geschlossen, Platten gesetzt, Torben im Raum/am Feuer/zu Hause. Alte Spielstände ohne Torben: `town_ore` startet erst, wenn `crafted_pickaxe` gesetzt ist; die Werkstatt-Zeile in `gustav_bench` bleibt kompatibel. **Laufende `sword_iron`-Aufträge bei Gustav** laufen unter dem alten `npc` zu Ende (Rezept-ID bleibt; nur neue Aufträge gehen an Torben, prüfen in `_work_orders`).

### 10.5 Dateien (Überblick)

`tools/art_torben.py`, `tools/art_torben_portrait.py`, `tools/prepare_torben_portrait.py`, `tools/art_town.py` (+ `smithy`), `tools/art_mine_props.py` (Erzader, Riss), `tools/art_items.py`/vorhandene Item-Skripte (Erz, Barren, Platte), `tools/audio_torben.py`; `assets/characters/torben*.png`, `assets/ui/portrait_torben*.png`, `assets/town/smithy*.png`, `assets/interior/torben_forge/`, `assets/audio/torben/`; `src/entities/npcs/story_torben.gd`, `src/entities/player/torben_*_scene.gd`, `src/entities/props/{void_crack,mine_door}.gd`; Tests (Abschnitt 12).

---

## 11. Reihenfolge der Umsetzung

Jeder Schritt ist einzeln spielbar/testbar.

| # | Schritt | Ergebnis |
|---|---|---|
| 1 | **Spike Mine-Tür** | Eine Tür in Ebene 3 führt in einen leeren Taschenraum und zurück; Entscheidung A (Interior) oder B (Raum). |
| 2 | **Eisen** | Items, Icons, Erzadern in der Mine, Quest-Garantie (≥ 6 Adern), Tests. |
| 3 | **Figur** | `art_torben.py` MVP-Clips, Rig, Kontaktbogen, Glow, Test. |
| 4 | **Porträt** | Quelle, Normalisierung, Backen der Mundformen, `act` und `grim/soft`. |
| 5 | **Schmiede-Teil** | Modell, Glow, Spill, Rauch, `smithy` in `town.json`, Vorschau-Capture, Test der Platzierung/`needs_resident`. |
| 6 | **Siedler + Shop** | `torben` in `settlers.json`, `torben_forge`, Rezepte, Chat, Vertrauen, Tagesplan, Test `test_town_story`. |
| 7 | **Quest `town_ore`** | Valdric, Mine, Erzaufgaben, Hämmern als Ton-Quelle. |
| 8 | **Quest `torben_forge`** | Tür, Taschenraum, Riss, Platten, Wellen, `StoryTorben`, `resume_story`. |
| 9 | **Rückweg, Begrüßung, `town_smithy`** | Szenen, Einzug, Dev-Sprung SCHMIEDE FERTIG. |
| 10 | **Man-Handling und Beziehungen** | zweite Clip-Lieferung, Funkenzone, Chatter-Paare, Raid. |
| 11 | **Doku und Abschluss** | `docs/town.md` + `docs/characters/torben.md` Stand, `CLAUDE.md`-Eintrag, Balancing. |

Schritte 2 bis 6 sind unabhängig von der Quest: Torben kann auch **vorab** als normaler Siedler mit Debug-Einzug testbar werden. Schritte 7 bis 9 hängen am Spike.

---

## 12. Tests

- `tools/test_torben_art.tscn`: Sheet-Maße, 8 Zeilen, Clip-Frames, Füße, Glow nur auf Glutpixeln, `strike` im Bereich.
- `tools/test_torben_portrait.tscn`: Mundform je Buchstabe, Haltezeit 0,10 s, Zeile `grim`/`soft`, Vergleich mit Ellie (Kopfhöhe, Schultern), `act`-Zeile umbricht korrekt.
- `tools/test_town_rules.tscn` erweitert: `smithy` braucht `torben`, Türzone frei, Licht, Kosten (inkl. Erz aus dem Lager).
- `tools/test_town_story.tscn` erweitert: Tagesplan Torben, Chat-Pools, Vertrauen 0/30/60, Produktion (2 Erz + 1 Holz → 1 Barren), Man-Handling-Cooldown.
- `tools/test_mine_ore.tscn`: ≥ 6 Adern je Ebene 1 bis 3 über 200 Seeds, Abbau, Speichern, Nachwachsen.
- `tools/test_torben_quest.tscn` (nach `test_gustav_quest.tscn`): Kette von `town_ore` bis `town_smithy` mit Zeitraffer, Tür, drei Wellen, `resume_story` an jedem Schritt, Migration alter Spielstände.
- Mehrspieler: `tools/test_torben_network.tscn` (zwei Prozesse), prüft Torben als Siedler (pure Funktion), Riss und Wellen als Host-Szene.

---

## 13. Risiken und offene Entscheidungen

1. **Taschenraum in der Mine** (Abschnitt 10.2): neu und ungetestet. Schritt 1 klärt das, bevor irgendetwas anderes davon abhängt.
2. **Dossier-Widerspruch: „nördliche Festungen“.** Die Überschrift §5 sagt „Die verlassene Zeche“, der Text „Großschmieden der nördlichen Festungen“, „Befehlshaber“. Das Festungs-Konzept ist verworfen (Personalraum-Neustart). **Vorschlag:** „Tiefschmieden der Zeche“, „Aufseher“, damit seine Vergangenheit und der Fundort in der Mine **eine** Geschichte sind: er hat die Tore der Tiefschmiede verriegelt, damit die Bergleute fliehen konnten, und ist selbst nie hinausgekommen, bis jetzt. Ich ändere das Dossier nicht ohne dein OK.
3. **Porträtquelle.** Gustavs, Maren und das Ritter-Porträt kamen mit Imagegen; ich habe in dieser Sitzung kein Bildgenerator-Werkzeug. Entweder du erzeugst die Quelle mit dem Prompt aus 4.4 und ich backe sie, **oder** ich rendere eine Büste aus dem Ellipsoid-Modell (konsistent zum Sprite, aber weniger gemalt). Empfehlung: gemalte Quelle.
4. **`sword_iron` zu Torben.** Das ändert Gustavs Rolle (`GUSTAV SCHMIEDET`). Empfehlung ja; Gustavs Humor trägt es (Chatter).
5. **Werkzeugstufen** (Stein/Eisen, `tier`, Erz-Tiers der Mine). Empfehlung: jetzt nur Daten-Feld, Mine-Tiers später.
6. **Hochheben immer erlaubt oder nur eine Szene?** Empfehlung: einmal je Spieltag je Spielerin (§9.3), in der Quest sowieso einmal fest.
7. **Sprecher-Anzeige:** Ellie kennt Torben schon vom Hörensagen? Empfehlung: Name TORBEN sofort (ohne Silhouetten-Stufe wie bei Valdric), weil Valdric und Gustav ihn nennen können; die Entscheidung entfällt, wenn du lieber ein erstes Treffen als „FREMDER“ willst (dann `known_flag` wie bei Gustav).
8. **Zeit.** 25 bis 30 Minuten Spielzeit, davon ein Drittel Erz sammeln. Messen und kürzen (Erzmenge 8 → 6), wenn es zäh ist.
9. **Gegner-Balancing** der Riss-Wellen, Plattenzeit (14 s) und der Sicherheitsfaktor, wenn Ellie nur mit dem Basisschwert kämpft. Messen mit Bot (`tools/test_*`-Muster).
10. **Maren.** Ihr Eintrag ist `enabled: false`; die Torben/Maren-Szenen werden erst aktiv, wenn sie freigeschaltet ist. Torben hängt nicht von ihr ab.
11. **Co-op.** Questszenen nur Host/Solo (wie alle). Torben als Siedler ist rein deterministisch und für alle sichtbar.

Bewusst **nicht** jetzt: Rüstungs-Instandsetzung (es gibt keine Haltbarkeit), Legierungen, Kohle als eigenes Item, Eisentor und Schutzräume (nur Datenhaken), Gamepad-Eingaben für `act`, Torben im Boss-Kampf.
