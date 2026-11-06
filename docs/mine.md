# Die Mine – Konzept

Status: **in Arbeit** (Schritte 1–9 gebaut, Optik von Zone 1 neu aufgebaut, Zonen 2–4 und Karte stehen noch aus; siehe Abschnitt „Stand der Umsetzung“ am Ende). Die Mine wird später von Quests eingeführt, wir bauen sie vorher als eigenständiges System. Dieses Dokument ist die Grundlage für die Schritte in Abschnitt 14. Es beschreibt Ziel, Regeln, Technik und Reihenfolge; Zahlen sind Startwerte, die in `data/mine.json` liegen und beim Balancing angepasst werden.

## 1. Vision und Designsäulen

Ein alter Mineneingang liegt auf der Karte. Dahinter führt eine Folge fester Ebenen immer tiefer: ein verschachteltes Geflecht aus Gängen und Räumen, labyrinthartig, mit Abkürzungen, Sackgassen und Schleifen. Auf jeder Ebene gibt es abbaubaren Fels (später Erz), Gegner und einen Abgang zur nächsten Ebene. Mit der Tiefe wird alles größer, härter und fremder.

Vier Säulen, an denen jede Entscheidung gemessen wird:

1. **Weg in die Leere.** Die Mine erzählt den Abstieg vom Menschlichen ins Void: von Holzstützen und Laternen über gehauenen Stein und Kristalladern bis zu Wänden, die atmen. Die Tiefe ist ein Ort, kein Zahlenwert.
2. **Licht ist Sicherheit.** Wo Lampen hängen, ist es sicher. Je tiefer, desto weniger Lampen und desto mehr eigenes Leuchten der Leere. Die Spielerin trägt weiterhin kein Licht.
3. **Jede Ebene ist ein Ort.** Feste Ebenen mit festem Layout, die man kennenlernt, Abkürzungen freischaltet und wiederfindet. Kein beliebiges Würfeln bei jedem Besuch.
4. **Besonders gestaltet, nicht einfältig.** Jeder Raumtyp hat eigene Props, Animationen, Geräusche und Gegnerkonstellationen. Keine austauschbaren leeren Kammern.

Abgrenzung: Auf der Oberwelt bleibt die Schwierigkeit überall gleich. Die Mine ist bewusst die Ausnahme: **hier wächst die Schwierigkeit mit der Tiefe.**

## 2. Entscheidungen

| Thema | Entscheidung |
|---|---|
| Persistenz | Jede Ebene ist fest: Seed und Layout ändern sich nie. Veränderungen (Abbau, Kills, Abkürzungen, Truhen) werden gespeichert, Details in Abschnitt 10. |
| Licht | Lampenketten an den Wänden, die mit der Tiefe seltener werden und durch Glimmpilze, Kristalle und Void-Adern ersetzt werden. Die Spielerin trägt kein Licht. |
| Tod | Standard des Spiels: Rückkehr zur Basis, nichts Zusätzliches geht verloren. |
| Rückweg | Pro Ebene eine Aufzugstation (Seilwinde). |
| Größe | Etwa 1,5× der ersten Schätzung: Ebene 1 ≈ 90×90 Tiles, tiefste Ebene ≈ 300×300 Tiles, dazwischen geometrisch interpoliert. Der Wert ist eine Annahme und steht als Parameter in der JSON-Datei. |
| Umfang | Vier Zonen zu je fünf Ebenen = 20 geplante Ebenen. Alle fünf Ebenen ein Wächter (Bossrhythmus). Das echte Boss-Design kommt später, bis dahin gibt es einen Platzhalter. |
| Umsetzung | Alles (Code, Art, Audio, Tests) entsteht direkt in Claude Code, ohne Subagents. Die Art-Pipeline nutzt die vorhandenen Python-Renderer. |

## 3. Struktur: Zonen, Ebenen, Größen

| Zone | Ebenen | Name (Arbeitstitel) | Charakter |
|---|---|---|---|
| 1 | 1–5 | Alte Stollen | Holzstützen, Schienen, Laternen, Lagerräume, Bergmannsspuren. Viel Licht. |
| 2 | 6–10 | Gehauener Stein | Mauerwerk, Treppen, Gewölbe, Schmiede, größere Hallen. Lampen werden lückenhaft. |
| 3 | 11–15 | Kristallgrotten | Natürliche Höhlen, Kristalladern, Glimmpilze, unterirdische Teiche. Kaum Lampen, kühles Eigenlicht. |
| 4 | 16–20 | Zerfressen | Risse mit magentafarbenem Licht, atmende Wände, Augenpaare in der Tiefe, Void-Blüten. Fast kein Menschenlicht. |

Wächter auf den Ebenen 5, 10, 15 und 20. Ebenen 1–4 sind „frei“, 5 endet an einer Wächterhalle. Die Zonen lassen sich später nach unten erweitern, ohne das Datenformat zu ändern (neue Zone = neuer Eintrag).

**Kantenlänge** `edge(n) = 88 · (304/88)^((n-1)/19)`, gerundet auf ein Vielfaches von 8 Tiles (Zellgröße, Abschnitt 4):

| Ebene | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Tiles | 88 | 96 | 104 | 112 | 112 | 120 | 128 | 144 | 152 | 160 |

| Ebene | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|
| Tiles | 168 | 184 | 192 | 208 | 216 | 232 | 248 | 264 | 280 | 304 |

Das sind 11×11 bis 38×38 Zellen. Die Ebene wächst also etwa um den Faktor 12 in der Fläche. Das ist die „längere und größere“ Mine, ohne dass jemand Stunden auf einer Ebene läuft: Die Wege wachsen mit der Kantenlänge, nicht mit der Fläche.

## 4. Eine Ebene: Aufbau und Generator

Der Generator ist eine **reine Funktion** `generate(world_seed, level) -> MineLayout` ohne Nodes. Sie läuft auf jedem Peer identisch und ist ohne Grafik testbar. Jede Phase hat einen eigenen Zufallsstrom (`seed = hash(world_seed, level, phase)`), sodass eine spätere Änderung an Props oder Gegnern das Layout nie verschiebt.

**Phasen**

1. **Zellgitter.** Die Ebene besteht aus Zellen zu 8×8 Tiles. Gänge sind in der Regel 3 Tiles breit, tiefere Zonen mischen schmale 2-Tile-Gänge und weite Hallen ein.
2. **Räume.** Rechteckige Räume aus 1×1 bis 3×3 Zellen werden platziert. Dichte und Größen kommen aus der Zone (`room_density`, `room_sizes`).
3. **Gerüst.** Ein zufälliger Spanning Tree (randomisiertes Kruskal) verbindet alle Räume und Zellen mit Gängen. Danach werden **Schleifen** hinzugefügt und ein Teil der Sackgassen entfernt (`braid`), aber nie alle: Sackgassen sind Orte für Truhen, Notizen und Fallen.
4. **Formung.** Die glatten Rechteckwände werden mit seeded Rauschen erodiert (Ausbuchtungen, Einbuchtungen, Nischen), ohne Verbindungen zu zerstören und ohne Engstellen unter der Körperbreite der Spinne.
5. **Schlüsselorte.** Der **Aufgang** (Ankunft von oben, auf Ebene 1 der Ausgang zur Oberwelt) wird am Rand gewählt. Der **Abgang** liegt am längsten Weg (BFS) davon entfernt, mindestens bei 85 % des Durchmessers. Die **Station** (Rastraum mit Aufzug) liegt bei 40–60 % des Weges, abseits der Hauptlinie. Auf Wächterebenen steht der Abgang in einer Wächterhalle.
6. **Kritischer Weg.** Aufgang → Station → Abgang ist immer frei begehbar. Blockaden (Einstürze) liegen nur auf Abkürzungen und in Seitenräumen, nie auf dem kritischen Weg.
7. **Raumtypen** (Abschnitt 5) werden nach Zonengewichten verteilt, mit Regeln zu Abstand, Pflichträumen und Maximalzahlen.
8. **Dekoration, Felsen, Lampenketten, Begegnungen** werden regelbasiert erzeugt (Abschnitte 6 bis 9).

**Ausgabe** `MineLayout`: `PackedByteArray` für Boden/Wand je Tile, Raumliste (Rechteck, Typ, Verbindungen), Graph, Schlüsselorte, Listen für Props, Felsen, Lampen, Begegnungen und Truhen, jeweils mit stabiler `id` (Hash aus Ebene und Zelle), die der Speicherstand verwendet.

**Prüfungen im Test** (für 200 Seeds je Ebene): alles Begehbare ist zusammenhängend, Aufgang/Station/Abgang sind verbunden, keine Engstelle unter 2 Tiles, der Abgang liegt weit genug vom Aufgang, die Erzeugung dauert unter 150 ms bei 88×88 und unter 800 ms bei 304×304 (läuft sonst kooperativ über mehrere Frames), identisches Ergebnis bei zwei Läufen.

## 5. Raumtypen

Jeder Raumtyp besitzt eine eigene Komposition, eigene Props, Animationen und Geräusche und eine Begegnungsvorlage. Zonen gewichten sie unterschiedlich.

| Raumtyp | Inhalt |
|---|---|
| **Kreuzung** | Gabelung mit Schienenweiche, Laternenpfosten, Wegmarken. Orientierungspunkt im Labyrinth. |
| **Lager** | Kisten, Fässer, Sackstapel, Werkzeugwand; Beute, oft bewacht. |
| **Schlafkammer** | Pritschen, Decken, Tagebuchseiten, ein Bergmann, der nicht mehr aufgestanden ist. |
| **Schmiede** | Esse mit Glut und Funken, Amboss, Wasserbecken, Blasebalg; warmes Licht, Geräuschkulisse. |
| **Kristallgrotte** | Hohe natürliche Höhle, Kristallcluster, die pulsieren; Rastplatz-Gefühl, aber nicht sicher. |
| **Überflutete Kammer** | Flaches Wasser (langsamer), Tropfstein, Spiegelungen, Fische als Lebewesen später. |
| **Einsturzstelle** | Schuttwand, die mit der Spitzhacke abgebaut wird, öffnet Abkürzung oder Seitenraum. |
| **Spinnennest** | Netze, Eier, dichte Gegnergruppe, gute Beute. |
| **Rastraum (Station)** | Lagerfeuer, Sitzplätze, Lampen, Aufzugswinde, ruhige Musik. Hier ist es sicher, keine Gegner beim Betreten. |
| **Wetterschacht** | Senkrechter Schacht mit Luftzug, Staub und Lichtstrahl von oben, wirbelt Laub und Staub auf. |
| **Wächterhalle** | Große Halle mit Siegel vor dem Abgang. Auf Wächterebenen Pflicht. |
| **Schatzkammer** | Versteckt, hinter einer Einsturzstelle oder am Ende einer langen Sackgasse. |

Zone 3 ergänzt natürliche Formen (unregelmäßige Höhlen), Zone 4 Void-Kammern (Risse, schwebende Fragmente, Augenpaare). Neue Raumtypen sind je ein Eintrag in `rooms` und eine Dekorationsfunktion.

## 6. Licht und Dunkelheit

- Die Ebene ist von Grund auf dunkel: eine eigene Umgebungsfarbe je Zone (`ambient`), wie bei den Innenräumen, mit `DayNight` verdrahtet.
- **Lampenketten** (`MineLampChain`): Wandlampen im Abstand von etwa 6 Tiles entlang der Hauptwege, ein Seil mit Lampen, das leicht schwingt. Jede Lampe ist ein weicher Lichtpool, der leicht flackert (wie `InteriorLight`).
- **Dichte pro Zone:** Zone 1 durchgehend, Zone 2 mit Lücken, Zone 3 nur noch an Kreuzungen und Räumen, Zone 4 gar keine. Die Lücken werden von Eigenlicht gefüllt: Glimmpilze, Kristalle, Void-Adern und Risse (alles „unlit“ wie bei den Wandvenen der Oberwelt).
- **Gameplay-Wirkung:** Lampenlicht ist Orientierung und Sicherheit. Der Listener reagiert auf Geräusche, die Spinnen auf Sicht; in dunklen Abschnitten schleicht man besser, im Licht sieht man mehr. Keine Regel „im Dunkeln Schaden“.
- **Rastraum:** hellster Ort der Ebene, eigener Lichtkreis.
- **Performance:** Lichter gehören zum Chunk und werden mit ihm gestreamt. Es gibt ein hartes Limit an gleichzeitigen Lichtern (Startwert 32), Lichter außerhalb der Sicht werden abgeschaltet.

## 7. Props, Animationen, Atmosphäre, Audio

**Props** (mit dem vorhandenen Ellipsoid-Renderer gebaut, `tools/art_mine.py` + Module): Holzstützen und Querbalken (mit Schimmelflecken), Loren auf Schienen (einige bewegbar), Schienen mit Weichen, Seilwinden, hängende und stehende Laternen, Kisten und Fässer, Spitzhacken und Werkzeug, Pritschen, Feuerstelle, Amboss, Schuttberge, Tropfsteine, Pfützen, Kristallcluster, Glimmpilze, Spinnweben, Skelette und Leichen von Bergleuten, Wegschilder mit Ebenenangabe, Tagebuchseiten (Lesen mit E).

**Animationen:** schwingende Lampen und Ketten, Funken und Flackern an Feuer und Esse, tropfendes Wasser mit Plätschern, Staubrieseln bei fernen Erschütterungen (ohne Gameplay), Luftzug im Wetterschacht, pulsierende Kristalle, Void-Risse mit eigenem Takt, atmende Wände in Zone 4, Fledermäuse als friedliche Ambient-Fauna in Zone 1–2.

**Boden und Oberflächen:** neue Oberflächen in `data/terrain.json`: `mine_stone` (normal), `mine_rail` (Metall, anderes Fußgeräusch), `mine_wet` (leicht langsamer, Spritzer), `mine_gravel`. Fußabdrücke und Schritte folgen dem, was man sieht.

**Audio:** synthetisierte Platzhalter wie bei den anderen Orten (`tools/audio_mine.py`): Tropfen, Holzknarzen, ferne Erschütterungen, Schienenklirren, Feuer, Windzug, Kristallsummen, Void-Brummen. Ambiente je Zone, Lautstärke und Anteile nach Ort im Raum; Hall in Hallen.

## 8. Abbau und Erze

- **Felsen** nutzen das vorhandene `Rock`-System (Spitzhacke, Stufen ganz → angeschlagen → klein → Schutt, Drops). Die Mine platziert sie regelbasiert: einzeln in Gängen, in Gruppen in Nischen, selten in Hallen. Ein Fels in der Mine hat die ID `(Ebene, Zelle)`.
- **Einsturzstellen** sind Schuttwände aus mehreren abbaubaren Brocken. Sie sperren nur Abkürzungen und Seitenräume.
- **Erzadern (Platzhalter jetzt):** eigene Fels-Variante mit sichtbarer Ader, `ore_tier` in den Daten (1–4 je Zone), liefert bis zum Erzsystem nur `stone`. So bleibt das spätere Erzsystem ein reiner Dateneintrag. Seltenheit sinkt mit der Tiefe (`ore_chance` je Zone), der Wert pro Erz steigt (`ore_tier`).
- **Nachwachsen:** gespeicherte Felsen wachsen nach der bekannten Regel zurück (`regrow_days`, Startwert 2 Tage), Einsturzstellen nicht.
- **Nicht in diesem Plan:** neue Wege durch Wände graben.

## 9. Gegner

**Verfügbar am Anfang:** `shadow_spider` und `void_listener` (Daten in `enemies.json`). Schwerere Gegner entstehen durch **Skalierung und Modifikatoren**, neue Arten kommen später als eigene Schritte.

- **Skalierung pro Ebene** (Startwerte): Leben ×(1 + 0,12·(n−1)), Schaden ×(1 + 0,06·(n−1)). Ebene 1 ×1,0, Ebene 20 ×3,3 Leben und ×2,1 Schaden. Die Werte liegen in `mine.json` und werden an die Spawn-Funktion übergeben.
- **Begegnungsbudget:** Jede Ebene hat ein Budget in Punkten, `budget(n) = Fläche/900 · (1 + 0,05·(n−1))`: Ebene 1 ≈ 9 Punkte, Ebene 10 ≈ 41, Ebene 20 ≈ 200. Kosten: Spinne 1, Listener 1,2, Elite 3. Das Budget wird auf Räume und Gänge verteilt, mit mehr Dichte in Nestern, Lagern und Wächterhallen; um Aufgang und Station herum bleibt ein sicherer Radius.
- **Begegnungsvorlagen** pro Zone (`encounters`): z. B. „zwei Spinnen von den Flanken“, „Listener deckt Spinne“, „Nest aus fünf kleinen und einer Elite“. Tiefere Zonen mischen mehr Arten und Hinterhalte.
- **Elite-Modifikatoren:** größere Skalierung, höherer Staggerwiderstand, mehr Leben, sichtbares Void-Merkmal. Ab Zone 2 möglich, ab Zone 3 häufiger.
- **Lebenszyklus:** Begegnungen **schlafen** im Raum und werden erst gespawnt, wenn ein Spieler näher als ca. 48 Tiles kommt. Gleichzeitig wache Gegner pro Ebene sind begrenzt (Startwert 14). Weit entfernte Begegnungen existieren nur als Daten.
- **Verhalten:** Navigation läuft über `EnemyNavigation` mit der Mine als `navigation_floor` (Rasterabfrage). Hören und Sehen wie bisher; Sneaken lohnt sich besonders in dunklen Abschnitten.
- **Wiederkehr:** getötete Begegnungen bleiben tot, bis die Ebene drei Spieltage lang unbesucht war; dann füllen sich Begegnungsräume nach (`respawn_days`). Wächter und Schatzkammer-Wachen kehren nicht zurück.
- **Bekannte Limitierung:** `enemy_id` ist bei Story-Spinnen auf Clients nicht repliziert. Die Mine braucht deshalb eine allgemeine, host-seitige Spawn-Funktion mit Replikation von Art, Skalierung und Modifikatoren (Schritt 8).

## 10. Fortschritt, Persistenz, Tod, Aufzug

**Pro Ebene gibt es:** Aufgang (Treppe oder Leiter hoch), Abgang (Treppe hinab), Station mit Aufzug.

- **Aufzug:** Die Station beginnt defekt (Kurbel/Seil klemmt). Eine kurze Interaktion macht sie nutzbar (Platzhalter, Quests können sie später an Items oder Aufgaben binden). Danach fährt man zur Oberwelt (Eingang) oder zu jeder anderen freigeschalteten Station. Von der Oberwelt aus kann man bis zur tiefsten freigeschalteten Station fahren; ohne Aufzug bleibt der Weg über die Ebenen 1 → n.
- **Ebenenwechsel:** Eine Treppe führt vom Abgang der Ebene n zum Aufgang der Ebene n+1 mit der bekannten Tür-Iris. Der Eingang führt auf Ebene 1.
- **Tod:** Standard des Spiels, Rückkehr zur Basis (`TestLevel.spawn_point()`), nichts geht zusätzlich verloren. Der Fortschritt der Ebene bleibt. Wer in der Mine stirbt, kehrt über Eingang oder Aufzug zurück.
- **Gespeichert** (`player`-unabhängig, im Weltteil des Speicherstands, `"mine"`): freigeschaltete Stationen, tiefste Ebene, pro Ebene: abgebaute Felsen und Einstürze (nach ID, Tag), Begegnungen (lebend/tot, Tag), geöffnete Truhen, gelesene Notizen, Wächter besiegt, Abkürzungen offen. Alles ist klein, in Dictionaries nach `id` wie `_thing_states`.
- **Beitretende Peers** erhalten den Stand der Ebene, in der sie sich befinden, per Snapshot.

## 11. Technische Architektur

**Bestehende Anknüpfungspunkte** (aus dem Code geprüft):

- `Interiors` baut alle Innenräume beim Start in Slots zu je 1600 px ab `POCKET_X0/POCKET_Y0` = 60000; `slot_at(pos)` klemmt auf höchstens 64 Slots und ist **nach oben nicht begrenzt**. Eine Mine an anderer Stelle würde daher fälschlich als Slot erkannt. Das muss zuerst behoben werden.
- Ein Innenraum ist maximal etwa 100×100 Tiles. Mine-Ebenen sind bis 304×304, werden bei Bedarf erzeugt und müssen **gestreamt** werden (wie Welt-Chunks).
- `WorldLevel.navigation_floor` liefert in Pockets bereits `true`; die Mine braucht eine genaue Rasterabfrage.
- `DayNight` nimmt `Interiors.ambient_color()`; die Mine liefert ihre Zonenfarbe auf demselben Weg.
- `WorldLevel._stream`, `MapDiscovery` und `MapWindow` nutzen `Interiors.outer(...)`, um die Position „draußen“ zu bestimmen; das muss für die Mine den Eingang liefern.
- Eingang: `data/ground.json` `huts` + `Hut` + `Doorway`, Türen-Iris `door_wipe.gdshader`.
- Felsen: `WorldProp`/`Rock`, `plants.json`; Gegner: `enemies.json`, `EnemyNavigation`; Licht: `InteriorLight`, `NightLight`; Speicher: `SaveGame`.

**Neue Bausteine**

| Datei | Aufgabe |
|---|---|
| `src/world/mine/mine_generator.gd` | Reine Funktion `generate(seed, level) -> MineLayout`. Kein Node, kein Szenenzugriff. |
| `src/world/mine/mine_layout.gd` | Datencontainer (Tiles, Räume, Graph, Listen). |
| `src/world/mine/mine_manager.gd` | Node in `WorldLevel` (Gruppe `mines`): baut Ebenen bei Bedarf, ordnet ihnen Slots zu, entfernt leere Ebenen nach einer Karenzzeit, beantwortet `level_at(pos)`, `navigation_floor`, `ambient`, `outer`. |
| `src/world/mine/mine_level.gd` | Eine gebaute Ebene: Chunk-Streaming von Boden, Wänden und Kollision, Props, Lichter, Felsen, Begegnungen. |
| `src/entities/props/mine_*.gd` | `MineEntrance`, `MineStairs`, `MineStation` (Aufzug), `MineLampChain`, `MineNote`, `MineChest`. Wo möglich Erweiterungen von `Interactable`, `Doorway`, `WorldProp`. |
| `data/mine.json` | Zonen, Größen, Raumtypen, Budgets, Skalierung, Lampen, Fels- und Beutetabellen. |
| `data/mine_notes.json` | Tagebuchseiten und Notizen (Platzhaltertexte). |
| `tools/art_mine.py` und Module | Tileset, Props, Eingang, Glowsheets. |
| `tools/audio_mine.py` | Platzhalteraudio. |
| `tools/test_mine_*.tscn` | Tests (Abschnitt 13). |
| `docs/mine.md` | dieses Dokument, später ergänzt um Bedienung und Stand. |

**Räume im Koordinatenraum:** Jede Ebene bekommt einen Slot von 6400 px (400 Tiles) in einer eigenen Zeile: `MINE_X0 = 60000`, `MINE_Y0 = 120000`, Slot `n` bei `x = MINE_X0 + n · 6400` (bis x ≈ 188000, die Genauigkeit von Float32 bleibt unter 0,02 px). Der erste Schritt prüft das gezielt (Kamera, Kollision, Schatten) und passt die Offsets an, falls Artefakte auftreten. `Interiors.slot_at` bekommt eine obere Grenze, die Positionsklassifizierung (`Welt`, `Innenraum`, `Mine`) liegt an einer Stelle.

**Darstellung:** 3/4-Ansicht wie die Oberwelt. Boden und Wand als `TileMapLayer` je Chunk (32×32 Tiles) mit Bitmask-Autotiles für Wandkanten; Wandflächen sind sichtbare Südfronten mit 1 Tile Höhe, Wandoberseiten dunkel. Kollision als zusammengeführte Rechtecke je Chunk. Y-Sortierung der Props wie überall (Füße unten Mitte). Eine kleine Prototypphase in Schritt 3 vergleicht Tilemap und Shader-Lösung und legt die Technik fest.

**Streaming und Performance:** Chunks um jeden Spieler (3×3), kooperativ vorbereitet und atomar eingehängt, im Geist von `docs/performance.md` und `WorldLevel.ChunkBuild`. Lichter, Props, Felsen und Begegnungen gehören zu ihrem Chunk. Eine Ebene ohne Spieler wird nach einer Karenzzeit (Startwert 60 s) freigegeben; ihr Zustand bleibt im Speicher als Daten.

**Multiplayer:** Der Host entscheidet (Abbau, Schaden, Begegnungen, Ebenenwechsel), jeder Peer erzeugt das Layout selbst aus dem Seed, Zustandsänderungen laufen als `@rpc` mit Prüfung auf dem Host. Spieler können auf verschiedenen Ebenen sein; Gegner und Physik sind je Ebene getrennt (eigener Slot). Gegner auf Ebenen ohne Spieler pausieren.

**Typisierung und Regeln:** Strikte Typisierung, Eingaben nur über `InputManager`, Daten in JSON über `DataRegistry`, kleine Komponenten, flache `.tscn` (CLAUDE.md).

## 12. Art-Pipeline (alles selbst, ohne Subagents)

Gleicher Stil wie die Oberwelt: 16×16-Tiles, 3/4, Licht oben links, Umrisslinie `1b1a2e`, violett-blaue Steinrampe (`STONE`) und die Baumrinde der Bäume (violett geädert), Void-Magenta und Teal für Eigenlicht. Vor jedem neuen Asset wird `docs/design_guide.md` gelesen und danach geprüft (Checklisten).

- **Tiles:** `tools/art_mine.py` (numpy, wie `art_grass.py`): Boden- und Wandatlas je Zone, Autotile-Layouts, Glow-Sheets mit nur den leuchtenden Pixeln. Läuft als `python3 tools/art_mine.py [preview.png]`, schreibt Atlas und Tileset-Resource und `data/mine_tiles.json`.
- **Props:** Ellipsoid-Renderer wie `hut_lib`/`art_quarry.py` (`big(k)`, Holz, Eisen, Stein, Kristall), Kontaktbögen als Preview.
- **Eingang:** gebaut wie `Hut` (eigene Looks-Tabelle), mit Rampe, Schienenstumpf, Lore, Warnschild und Tor.
- **Prüfung:** Kontaktbogen, Icon-Check wo Items betroffen sind, Screenshot im Spiel bei Tag und bei Nacht der Oberwelt (Eingang) und in der Mine.
- **Reihenfolge:** Zone 1 vollständig zuerst. Zonen 2–4 reusen Generator und Systeme und tauschen nur Palette, Tiles, Raumdekoration und Audio aus.

## 13. Tests

Alles als `tools/test_mine_*.tscn`, headless wo möglich:

- **Generator:** 200 Seeds je Ebene 1, 5, 10, 20 – Zusammenhang, Schlüsselorte, Engstellen, Wegelängen, Blockaden nie auf dem kritischen Weg, Determinismus, Laufzeit.
- **Aufbau:** Streaming (Chunks laden/entladen, Kollision stimmt mit Layout überein, Navigationsabfrage), Positionsklassifizierung ohne Überschneidung mit `Interiors`.
- **Gegner:** Budget wird eingehalten, Skalierung, Schlafen/Wecken/Spawnen, Wiederkehr.
- **Abbau:** Zustand, Nachwachsen, Einsturz öffnet Weg.
- **Fortschritt:** Ebenenwechsel, Station freischalten, Aufzug, Tod, Speichern/Laden, Neustart.
- **Netzwerk:** zwei Prozesse (Host/Client): Beitritt in einer Ebene, Abbau und Kills sichtbar, Spieler auf verschiedenen Ebenen, Ebenenwechsel eines Clients. Eigener Loopback-Port.
- **Performance:** Aufbauzeit pro Chunk, Lichter-Limit, Speicher bei 304×304.
- **Sichttest:** Screenshots je Zone mit `-- --capture=` (kein Ersatz für Spielen, aber gegen offensichtliche Fehler).

## 14. Bauplan in Schritten

Jeder Schritt endet lauffähig, mit eigenem Test und kurzem Eintrag in diesem Dokument. Die Modellvorschläge nennen Modell und Aufwand (Effort).

| # | Schritt | Inhalt | Abnahme | Modell / Aufwand |
|---|---|---|---|---|
| 1 | **Fundament** | Positionsklassifizierung `Welt/Innenraum/Mine` (obere Grenze in `slot_at`), `MineManager`-Gerüst, Slot-Zuordnung, Float-Test der hohen Koordinaten, `data/mine.json` mit Zonen und Größen, `outer`/`ambient`/`navigation_floor`-Anbindung | Bestehende Interiors unverändert; ein leerer Mine-Slot ist betretbar (Debug), Kamera stabil | Opus 5.5, high |
| 2 | **Generator** | `mine_generator.gd` mit allen Phasen (Zellen, Räume, Gerüst, Schleifen, Formung, Schlüsselorte, kritischer Weg), Layout-Container, Debug-Viewer als 2D-Szene | Generator-Test (200 Seeds), Laufzeiten, Viewer zeigt alle 20 Größen | Opus 5.5, xhigh |
| 3 | **Aufbau (Graubox)** | `MineLevel` mit Chunk-Streaming, Tilemap/Shader-Prototyp und Entscheidung, Kollision, Navigationsabfrage, Kamera-Limits, Debug-Zugang (Entwickler-Tab: „Mine betreten“) | Graubox-Ebene 1 und 20 laufbar, sauberes Streaming, keine Frame-Spitzen | Opus 5.5, high |
| 4 | **Art Zone 1** | `art_mine.py`: Boden- und Wandatlas, Autotiles, Glow-Sheets, Kernprops (Stützen, Lampen, Lore, Schienen, Kisten, Schutt), Eingangsgebäude, Treppen | Kontaktbogen, Eintrag in `docs/design_guide.md`-Checkliste, Screenshots | Fable 5.1, high |
| 5 | **Licht, Atmosphäre, Audio** | `MineLampChain`, Zonenfarbe, Lichtlimit, Staub, Tropfen, Wetterschacht-Effekt, Oberflächen in `terrain.json`, `audio_mine.py` | Zone 1 wirkt fertig atmosphärisch, Lichterlimit funktioniert | Sonnet 5.5, high |
| 6 | **Raumtypen und Dekoration** | Alle Raumtypen von Zone 1 mit Props, Animationen, Regeln, Raumvorlagen, Notizen und Truhen | Jeder Typ erkennbar, Screenshots, keine Props in Wänden | Opus 5.5, high |
| 7 | **Abbau** | Felsen, Einsturzstellen, Erzadern-Platzhalter, Zustand und Nachwachsen, Speicherformat des Weltteils `"mine"` | Test: abbauen, speichern, laden, nachwachsen | Sonnet 5.5, high |
| 8 | **Gegner** | Allgemeiner Host-Spawn mit `enemy_id`-Replikation, Skalierung, Begegnungsbudget, Vorlagen, Schlafen/Wecken, Wiederkehr, Elite-Modifikatoren, sichere Radien | Tests Budget, Skalierung, Netzwerk (Client sieht Typ und Werte) | Opus 5.5, xhigh |
| 9 | **Ebenenwechsel, Station, Fortschritt** | Eingang → Ebene 1, Treppen, Station mit Aufzug, Freischaltung, Tod/Respawn, Speichern/Laden, Anzeige der Ebene im HUD | Alles von Eingang bis Ebene 3 spielbar, Neustart behält Stand | Opus 5.5, high |
| 10a | **Zone 2** (Ebenen 6–10) | Palette, Tiles, Treppen/Gewölbe, Schmiede, Lampenlücken, Audio, Gegnertabelle | Screenshots, Generator-Test für Ebene 6–10 | Fable 5.1, high |
| 10b | **Zone 3** (11–15) | Natürliche Höhlen, Kristalle, Teiche, Eigenlicht-System, Audio | wie oben | Fable 5.1, high |
| 10c | **Zone 4** (16–20) | Void-Optik, Risse, atmende Wände, Augenpaare, Audio, härteste Tabellen | wie oben | Fable 5.1, xhigh |
| 11 | **Wächter-Platzhalter** | Wächterhalle, Siegel am Abgang, Platzhalter-Elite, Flag „besiegt“, Speicherung | Ebenen 5, 10, 15, 20 abschließbar | Sonnet 5.5, medium |
| 12 | **Minenkarte** | Entdeckungsgitter pro Ebene (Nebel wie `MapDiscovery`), M öffnet die Ebenenkarte, Markierung von Stationen und Treppen | Karte füllt sich, wird gespeichert | Sonnet 5.5, high |
| 13 | **Härtung** | Multiplayer-Tests (verschiedene Ebenen), Performance auf 304×304, Speicherfreigabe, Fehlerfälle (Absturz in der Ebene, Spieler entfernt) | Alle Tests grün, Messwerte in `docs/performance.md` | Opus 5.5, xhigh |
| 14 | **Balancing und Doku** | Zahlen in `mine.json` anpassen, Dokumentation, Eintrag in `CLAUDE.md` | Spieltest 1–20 mit Notizen | Sonnet 5.5, medium |

**Reihenfolge-Begründung:** Erst Daten und Generator ohne Grafik (Schritte 1–2), weil dort die meisten Fehler entstehen und sie testbar sind. Dann ein sichtbares Skelett (3), danach Art (4) und Atmosphäre (5), erst dann Inhalt (6–8). Systeme für Fortschritt (9) vor den übrigen Zonen, damit alles früh spielbar ist. Zonen 2–4 sind Variationen desselben Systems. Karte und Wächter kommen spät, weil sie auf allem aufbauen.

**Modellwahl:** Fable 5.1 und Opus 5.5 für Schritte mit harter Logik, Netzwerk oder viel gestalterischer Entscheidung; Sonnet 5.5 für klar umrissene Erweiterungen auf vorhandenem Gerüst. Wenn ein Schritt länger als geplant dauert oder die Qualität nicht reicht, wechselt er eine Stufe nach oben.

## 15. Risiken, offene Punkte, Backlog

**Risiken**

- **Float-Genauigkeit** bei Koordinaten über 100000 px (Kamera, Kollision, Schatten): wird in Schritt 1 gemessen.
- **Generatorlaufzeit** bei 304×304: Messung in Schritt 2, notfalls kooperativ oder in einem Thread.
- **Licht-Kosten:** viele `PointLight2D` kosten Fill-Rate. Gegenmittel: Limit, Culling, Lichter an den Chunk binden.
- **Wanddarstellung in 3/4:** Autotiles und Südfronten sind aufwendig; deshalb der Prototypvergleich in Schritt 3.
- **`enemy_id`-Replikation:** Voraussetzung für die Gegner (Schritt 8).
- **Lesbarkeit im Labyrinth:** ohne Karte schwierig; Wegmarken, Schilder und die Karte (Schritt 12) sind deshalb Teil des Plans.

**Annahmen, die du jederzeit ändern kannst**

- 1,5× bezieht sich auf meine vorgeschlagenen 60×60 und 200×200 Tiles (also 88 und 304 mit Rundung auf Zellen).
- Gegner kehren nach drei unbesuchten Tagen zurück, Felsen nach zwei Tagen.
- 20 geplante Ebenen; Erweiterungen später.
- Der Aufzug beginnt defekt und wird mit einer kurzen Interaktion repariert (Platzhalter für spätere Quests).

**Backlog (nicht in diesem Plan)**

- Echtes Boss-Design und Wächter-Mechaniken.
- Echte Erze, Schmelzen, Handwerk, Items aus der Tiefe.
- Neue Gegnerarten (Wandkriecher, Stollenwurm, Void-Schwarm).
- Fallen, Einsturz-Ereignisse mit Spielfolgen, Gasdunst.
- Gräben in Wände, Sprengen.
- Questverknüpfung, Dialoge, Bergmann-NPCs.
- Musik pro Zone.


## Stand der Umsetzung (2026-11-05)

**Gebaut und getestet** (`tools/test_mine_*.tscn`): Fundament, Generator, Aufbau mit Chunk-Streaming, Props und Räume, Licht und Audio, Truhen und Notizen, Abbau (Felsen über das Prop-System der Welt, Einsturzstellen), Gegner (Budget, Skalierung, Schlafen/Wecken, Wiederkehr), Eingang auf der Karte, Treppen, Aufzug samt Menü, Speichern, Ebenenanzeige.

**Optik (Zone 1 neu, nach Rückmeldung „Boden langweilig, Wände blockig und klein, alles kahl“):**
- **Form:** `MineField` rundet das Kachelraster pro Chunk zu einem weichen Feld (4-px-Zellen, zweimal Box-Blur, zwei Oktaven Rauschen); die Kontur bei 0,5 ist die Kante. Die Mitte jeder Kachel behält ihre Art (Säulen und Lücken von einer Kachel bleiben). Die Kollision ist diese Kontur als Liniensegmente (`ConcavePolygonShape2D`, Marching Squares, Chunks schließen exakt aneinander): Bild und Kollision sind dieselbe Kante.
- **Malen:** `assets/shaders/mine_terrain.gdshader` malt einen Chunk einmal in eine Textur (`MineChunk._bake`, SubViewport, danach ein `Sprite2D`), also keine Kosten pro Frame. Boden je Raumtyp (`MineField.kind_of`: Fels mit Rissen und Geröll, Flagsteine, Dielen, Schlamm, dunkle Erde, Asche, Schotterbett unter den Schienen); Wandfläche 40 px hoch (Zonenwert `terrain.face`) aus gebrochenem Fels (Facetten, Risse, Schichten, Tropfspuren, Moos, Erzflecken, Tropfsteinzähne unter der Kante), einzelne Buchten gemauert, ein Teil mit Holz verzimmert (Pfosten, Balken, Bretter); Felskopf dahinter mit Rissen, hellem Rand und seltenen Glitzerpunkten. Paletten je Zone in `data/mine.json` (`terrain`).
- **Leben:** `MineClutter` (Schienenlinie entlang des Hauptwegs mit Kurven, Schutthaufen, Bretter, Werkzeug, Eimer, Seil, Glimmpilze, Laterne am Boden, Leiter und Kette an der Wand), `MineBats` (Fledermäuse in den oberen Ebenen), mehr Raumkompositionen. Dichte: `clutter` pro 1000 Bodenkacheln je Zone.
- **Immer Nacht:** In der Mine gilt unabhängig von der Uhrzeit nur der dunkle Zonenton (`DayNight` schaut `Mines` bei jedem Frame nach, nicht nur in `_ready`); alles, was von der Tageszeit abhängt (`NightLight`, Glow-Sheets, `HutYard`), fragt `MineManager.night_at(...)` und bekommt dort immer „Nacht“. Bodennahe Effekte (Angriffsanzeigen der Gegner `z -3`, Schattenflecken und Blut `z -4`) liegen über dem Boden der Mine (`z -6`).
- **Schienen** (`MineClutter._rails`): eine durchgehende Kette aus Nachbarkacheln pro Gang (Hauptweg, jeder Gang an einer Kreuzung, ein Teil der übrigen), im Raum bis zur Mitte; Kurven passend zu den Atlaskacheln (2 W-S, 3 W-N, 4 O-N, 5 O-S), Test `tools/test_mine_look.tscn`.
- **Felsen der Mine:** `tools/art_mine_rocks.py` (derselbe Renderer wie die Weltfelsen, andere Palette und Formen, keine Kristalle) → `assets/mine/props/mine_rocks.png` und die Schutthaufen `rubble_a|b|c`. Wandgebundene Props (Lampen, Leitern, Ketten) werden auf die echte Kante gesetzt (`MineChunk.wall_edge`).
- Vorschau: `tools/preview_mine.tscn -- --level=N --rooms=typ,typ --capture=/abs/datei.png` (OpenGL-Treiber), Eingang: `tools/preview_mine_gate.tscn`. Bilder: `docs/img/mine_*.png`.

**Offen:** Zonen 2–4 (Paletten, Raumkompositionen für Schmiede, Kristallgrotte und Void-Kammer sind als Props vorhanden und in den Räumen verdrahtet, aber optisch nicht nachgezogen), Minenkarte, Härtung (Mehrspieler auf verschiedenen Ebenen, Performance bei 304 × 304), Balancing. Bewusst noch nicht: Elite-Modifikatoren, Bosse, neue Monster, Erze.
