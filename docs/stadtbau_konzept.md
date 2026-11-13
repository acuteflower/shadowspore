# Stadtbau 2.0 – Konzept „Jeder Bau ist ein Ereignis"

Status: **gebaut in drei Schritten (2026-11-13)**, siehe Abschnitt 10 (was wie umgesetzt ist, Abweichungen, offen). Grundlage: `docs/town.md` (Regeln, Daten, Netz), `src/town/build_menu.gd`, `build_mode.gd`, `town_structure.gd`, `town_banner.gd`, `assets/shaders/build_pixels.gdshaderinc`. Ältere Ausbau-Ideen (Lampenpflege, Klappen, Bank, Abnutzung …) stehen in `docs/town_ausbau.md` und sind großteils gebaut; dieses Dokument berührt sie nicht.

## 0. Was heute fehlt (Befund)

Das System ist technisch solide (Licht ist Land, Host prüft, Trampelwege, Pixel-Aufbau), aber es **fühlt sich wie Verwaltung an, nicht wie Erschaffen**:

| Moment | Heute | Problem |
|---|---|---|
| Menü öffnen | dünner Zweig über der Hotbar, Anhänger mit kleinem Icon, Papierblatt mit Text | Man sieht nicht, *was* man baut. Gesperrte Teile sind unsichtbar, also kein „das will ich als Nächstes". Keine Anzeige, wohin die Stadt wächst. |
| Vorschau in der Welt | durchscheinendes Bild, türkis/rot | Wirkt wie ein Editor, nicht wie ein Bauplan. Was beim Setzen weggeräumt wird, sieht man nicht. |
| Setzen | Material weg, Seilrahmen erscheint, Toast „ANGELEGT" | Kein Grundstein-Gefühl. |
| Bauen | Spielerin steht daneben, Pixel fallen ein, Klopfen alle 0,9 s | Passiv. Man wartet, statt zu bauen. |
| Fertig | 22 Staubpartikel, kurzer Hüpfer, ein Holzton | Der größte Moment ist der kleinste Effekt. |
| Stadt betreten | Goldtext oben, dünne Linie, einmal am Tag | Kein Ort-Gefühl, keine Identität der Stadt. |
| Stufe steigt | derselbe Goldtext | Kein Ansporn, keine sichtbare Belohnung. |

Leitbild für alles Folgende: **Wählen → Grundstein → Anpacken → Lichtweihe → Die Stadt antwortet.** Jeder Schritt hat einen eigenen, lesbaren Moment, und jeder Moment zeigt, wohin es als Nächstes geht.

## 1. Das neue Baumenü: „Der Bauplan"

Bleibt im Rankenstil (VineStyle, PixelText, keine Kästen), wird aber vom Streifen zum **Bauplan-Tisch** am unteren Bildrand (ca. 640 × 112, die Hotbar faltet sich solange weg, `Hotbar.FOLD`-Mechanik vorhanden).

### 1.1 Aufbau (links → rechts)
1. **Kategorien** als hängende Schilder am Ast (wie heute), jedes mit einer kleinen Zahl „baubar / gesamt".
2. **Teile als Bauplan-Karten** an einer Ranke: Rindenpapier-Kärtchen 40 × 48 mit dem **echten Bild des Teils** (herunterskaliert in ganzen Pixeln, `preview` aus town.json), Name, Kosten-Chips darunter. Zustände:
   - **baubar**: Bild in Farbe, sanftes Atmen.
   - **fehlt Material**: Bild in Farbe, fehlende Chips rot, Karte leicht gesenkt.
   - **gesperrt**: Bild als **teal Bauplan-Silhouette** (derselbe gepunktete Look wie der unfertige Pixel-Aufbau), darunter in Lila *warum*: „BRAUCHT WERKSTATT", „AB DORF", „BRAUCHT GUSTAV". *Das ist der Ansporn: man sieht immer, was als Nächstes kommt.*
   - **Limit erreicht**: Karte grau, „3/3".
3. **Die große Karte** des gewählten Teils (rechts, ca. 150 × 96): **Live-Mini-Bau** – das Teil baut sich im Loop mit dem echten `build_pixels`-Shader zusammen (Fortschritt 0→1 in 2,5 s, kurz fertig, wieder von vorn). Darunter: Bauzeit, Lichtreichweite („+7 FELDER LICHT"), Stadtwert („+12 WERT"), was es freischaltet („SCHALTET FREI: SCHMIEDE"), Beschreibung.
4. **Stadt-Leiste** oben rechts über dem Ast: Stufenname, Wert-Ranke bis zur nächsten Stufe (Saft füllt sich, „42 / 70 → DORF"), beim Überfahren des gewählten Teils **leuchtet der Zugewinn vor** (die Ranke zeigt in Gold, wie weit dieses Teil sie füllen würde). Erreicht ein Teil die nächste Stufe, blinkt dort „STUFE!".

### 1.2 Öffnen und Wechseln
- Öffnen (B): der Ast wächst wie heute aus der Mitte, dann **klappen die Karten nacheinander herunter** (40 ms Versatz, Überschwingen), Papier-Raschel-Sound.
- Kategorie wechseln: Karten drehen sich wie Spielkarten weg und neue kommen (Scheibe in 2-px-Schritten, keine Rotation).
- Teil wählen: Karte hebt sich, ein Blütenkranz öffnet sich darüber (vorhandenes `_bloom`, größer).
- Bei Nacht frisst die Leere wie heute die Ranken-Enden an.

### 1.3 Die Vorschau in der Welt: „Bauplan statt Geist"
- Das Teil steht als **projizierter Bauplan** da: teal gepunktete Pixel (gleicher Shader wie die Baustelle bei Fortschritt 0, Parameter `ghost` = 1), Kontur aus hellen Linien, die langsam „gezeichnet" umlaufen. Ungültig: die Punkte werden rot, zittern, und an der Stelle des Hindernisses blinkt ein kleines rotes Kreuz (wir kennen den Grund aus `check_place`; für Kollisionen liefert `town_probe` die Stelle).
- **Was weggeräumt wird, zeigt sich vorher**: Büsche, Gras, Pilze in Fußfläche + Druckwellenradius (Abschnitt 4) wackeln leicht und bekommen einen dünnen weißen Umriss. Man sieht, dass das Bauen aufräumt.
- **Lichtrand**: Die wandernden Punkte des Baugebiets bleiben; für Teile mit `reach` zeigt die Vorschau zusätzlich den **neuen Lichtkreis** als gestrichelten Goldring, und die Fläche, die neu dazukommt, schimmert schwach. *Man sieht, wie die Stadt wächst, bevor man klickt.*
- Raster: kurze Kreuzchen nur in 48 px um den Cursor (statt nichts / ganzes Gitter), das gewählte Snap-Feld rastet mit einem Tick-Sound ein.

## 2. Setzen: der Grundstein (0,7 s)

1. Klick → ein **Grundstein** (kleiner Steinblock mit Rune, Sprite 12 × 10) fällt aus 40 px auf den Fußpunkt, schlägt ein: Staubring, kleiner Kamera-Ruck (nur die Bauende), tiefer „Klonk".
2. Vom Grundstein aus **zieht sich der Bauplan auf**: die Pixelreihenfolge (`bp_order` im Shader) wird einmal rückwärts als Lichtwelle durchlaufen, sodass das ganze Teil für 0,4 s als teal Drahtgitter aufblitzt und dann zu den matten Bauplan-Punkten absinkt.
3. **Material fliegt ein**: die Kosten-Icons lösen sich als kleine Bögen von der Spielerin (Rucksack) bzw. vom Vorratslager (Stadtlager, wenn geladen) und landen auf einem Materialhaufen neben der Baustelle (ein kleiner Stapel-Sprite je Material, verschwindet mit dem Fortschritt). Nur Optik, auf jedem Peer aus den Kosten berechnet.
4. Pflöcke schießen in den Boden, das Seil spannt sich (heutiger Seilrahmen, jetzt mit Ein-Animation).

Netz: nichts Neues; `_rpc_added` reicht, jeder Peer spielt den Grundstein selbst ab, wenn eine Struktur mit `g == 0` neu hinzukommt (nicht bei Snapshot/Laden).

## 3. Bauen: Anpacken statt Warten

### 3.1 Hand anlegen (E halten)
- Heute baut Anwesenheit. **Bleibt** als Grundrate (niemand wird bestraft), aber an jeder Baustelle steht ein Prompt **„E ANPACKEN"**. Halten: Ellie spielt einen **Hammer-Clip** (neues Werkzeug `hammer_build` nur als Optik in der Hand über das Griff-System, `grips.json` Stil `top_down` wie die Axt; der Körper nutzt die vorhandene Axt-Hiebanimation, kein neues Sheet nötig).
- Jeder Schlag (≈ 0,55 s): **Fortschritt-Schub** (+100 % Rate solange sie anpackt, d. h. Anwesenheit 1×, Anpacken 2×; mehrere Anpackende addieren sich wie Helfer heute), ein **Schwall Pixel** fliegt sichtbar ins Bild (Shader-Parameter `burst`: die nächsten ~60 Pixel der Reihenfolge fliegen nicht aus 7 Reihen, sondern aus der Richtung der Spielerin heran, mit Funkenschweif), Hammerton, Staub, Kamera-Nicken klein.
- Host-autoritativ: Owner sendet `anpacken an/aus`, Host zählt es in die Rate (`_helpers` bekommt eine Gewichtung). Schlagtakt ist reine Optik auf jedem Peer.
- Siedler am Arbeitsplatz zählen wie heute; Gustav mit Hammer-Clip, wenn er hilft (Haken, nicht Pflicht).

### 3.2 Die Baustelle lebt
- **Gerüst**: prozedural aus dem Fußrechteck (`TownStructure._draw`): Pfosten an den Ecken, Querbretter je 16 px Höhe, wächst mit dem Fortschritt nach oben *vor* der Baufront her, ist bei 100 % verschwunden (Abschnitt 4). Holzfarben aus `VineStyle`/`FRESH_RAMPS`. Kein Bild nötig.
- **Baufront**: entlang der aktuellen Bauhöhe treiben ein paar teal Funken waagerecht, die Front selbst glimmt (im Shader schon angelegt: „dichter an der Baufront"; Glow verstärken).
- **Abschnitte**: die `window`-Teile (Dach, Laterne, Banner …) schließen mit einem eigenen kleinen Moment ab: Ruck, Staub, eigener Ton (Dachziegel-Klappern, Glas-Ping). Daten: optional `"done_fx": "roof"|"glass"|"cloth"` an `parts`.
- **Meilensteine** 25 / 50 / 75 %: tieferer Schlag, kleiner Staubring am Fuß, die Fortschrittslinie am Seil blinkt.
- **Fortschritt lesbar**: über der Baustelle schwebt (nur in 120 px Nähe) eine kleine Ranke mit Prozent und „×2" während des Anpackens.

## 4. Fertig: die Lichtweihe und die Druckwelle (≈ 2,4 s)

Der Höhepunkt. Ablauf auf jedem Peer gleich, Zeit 0 = `_rpc_done`:

| t (s) | Was passiert |
|---|---|
| 0,00 | Letzte Pixel schießen ein, das ganze Bild **blitzt weiß-teal** (Glow-Pass 1,0), Gerüst und Seilrahmen **fliegen auseinander** (Bretter als kleine Trümmer-Partikel nach außen, fallen, verblassen). |
| 0,15 | Das Teil **setzt sich**: Squash 1,0 → 0,94 hoch / 1,06 breit → Überschwingen → 1,0 (in ganzen Pixeln: Sprite-Offset, keine Skalierung des Pixelbilds; Squash nur über 1-px-Versatz der Kanten im Shader, damit es pixelrein bleibt). Tiefer Einschlag-Ton + heller Glockenton. |
| 0,20 | **Druckwelle** läuft vom Fußpunkt los (siehe 4.1). Kamera-Shake nach Entfernung (`Player.add_shake`, bis 360 px). |
| 0,20–1,0 | Die Welle räumt (4.2). Bäume am Rand schwanken (`FirTree._shake`, Nadelregen), Vögel fliegen auf, Hasen flüchten (`WildlifePopulation` Lärm-Ereignis wie ein Schwerthieb mit großem Radius). |
| 0,9 | Bei Teilen mit `reach`: **das Licht flutet** – der Lichtkreis wächst von 0 auf seinen Radius (NightLight-Energie + die Baugebiets-Punkte laufen sichtbar nach außen), nachts ein warmer Schwall über den Boden. |
| 1,2 | Kleiner Schriftzug **in der Welt** über dem Teil (nicht Bildschirmbanner): Name in Gold, darunter „+12 WERT", steigt auf, zerfällt in Funken. Der Wert fliegt als Funke zur Stadt-Leiste, falls das Menü offen ist. |
| 2,4 | Ende. Erreicht der Bau eine neue Stufe, startet jetzt die Stufen-Zeremonie (Abschnitt 5.2). |

Die heutige `_finish_fx` wird ersetzt; der Ablauf läuft in einem eigenen kleinen Knoten `TownConsecration` (src/fx), damit `TownStructure` schlank bleibt.

### 4.1 Die Welle (Optik)
- Ein Boden-Shader-Quad (`town_wave.gdshader`, unshaded, z −5 über dem Boden, unter Figuren): ein Ring, der mit 260 px/s bis zum Radius `wave` läuft. Am Ring: **heller Lichtsaum** (teal → gold), dahinter ein **Staubwall** aus Pixeln, davor eine kurze **Verzerrung** des Bodens (Bildschirm-Textur um 1 px versetzt, wie `listener_shock.gdshader`). Hinter der Welle bleibt für 1,5 s ein **frisch geglätteter Boden**: das Gras ist flach gedrückt (MeadowDetails-Kontaktfeld bekommt den Ring als „Akteur", die Halme biegen nach außen und richten sich langsam wieder auf).
- Radius je Teil in `town.json` neues Feld `wave` (px, Vorschlag: Lichtpfosten 40, Zaun/Platte 0 = keine Welle, Bank/Standarte 24, Lager 72, Werkstatt 88, Schmiede 96, Questtafel 40, Feld 0 – Felder räumen nur ihre Fläche). Die Welle reicht nie über das Lichtgebiet hinaus (wird daran abgeschnitten).

### 4.2 Was die Welle räumt (Regel)
- **Weiche Props** (`soft_kinds`: Busch, Beerenbusch, Glutbrombeere, Gras, Kiesel, Pilze, Flora, Stümpfe, erschöpfte Felsen) im Kreis `wave` um den Fuß werden **entwurzelt**: im Moment, in dem der Ring sie erreicht (Verzögerung = Abstand / Geschwindigkeit), springen sie hoch, zerplatzen in Partikel ihrer eigenen Farben (`pickup.burst` / `leaf_colors`, vorhandenes `WorldProp`-Burst) und fliegen nach außen weg. Danach sind sie dauerhaft weg (`cleared`, wie die Fußfläche heute).
- **Nicht** geräumt: Bäume, Felsen, Erz, Wasserpflanzen, Story-Props, Kleeblumen (Kleefelder werden nur im Fuß wie heute behandelt), Rätsel/Truhen. Bäume schwanken nur.
- **Ertrag** (Vorschlag, siehe offene Entscheidung 1): was entwurzelt wird, gibt **ein Drittel** seines normalen Sammel-Ertrags ins **Stadtlager** (Fasern, Beeren, Steine, Pilze), sichtbar als kleine Item-Funken, die zum Vorratslager fliegen. Aufräumen fühlt sich dann nach Ernte an, nicht nach Verlust.
- Host: beim Fertigwerden `world.town_soft_cells_circle(center, wave)` (neue Variante der vorhandenen Rechteck-Funktion, auf das Lichtgebiet beschnitten) → `_rpc_done(id, cells)` trägt die Zellen mit; jeder Peer entfernt sie zeitversetzt mit der Animation; gespeichert wie bisher in `cleared`. Ein Peer, der die Zelle nicht geladen hat, trägt sie nur ein.
- Die Regel „Verbrauchtes bleibt auch im Licht" (`town.md`) bleibt unberührt: sie betrifft geerntete Pflanzen; die Welle ist eine bewusste, einmalige Räumung um ein neues Gebäude.

## 5. Die Stadt antwortet

### 5.1 Stadt betreten: das Stadtbanner
Ersetzt den heutigen Goldtext beim Betreten (`TownManager` „_inside"-Logik bleibt, Auslöser: einmal pro Tag **oder** nach mehr als 3 Spielminuten außerhalb).
- **Ein Stoffbanner rollt sich vom oberen Bildrand herab** (ca. 220 × 64): Stoff in der **Stadtfarbe** (5.3) mit Goldborte und Schwalbenschwanz, gehalten von einer Querstange aus Ranke; das Tuch hängt im Wind (Reihen verschieben sich in ganzen Pixeln wie `sway_rows.gdshader`), in der Mitte das **Wappen** (5.3), darunter der **Name** groß in Gold (`PixelText` 3×), darunter klein „DORF · 14 EINWOHNER · TAG 23". Nachts glimmt die Borte, die Leere frisst die Stangenenden an.
- Gleichzeitig in der Welt: an ihren Füßen **kräuselt sich der Lichtrand** (die Baugebiets-Punkte laufen als Welle einmal um sie herum), alle Laternen in Sichtweite flackern kurz auf, ein kurzes Leitmotiv (4 Töne, `tools/audio_town.py`).
- Rollt nach 3 s wieder hoch. Abbrechbar durch Menüs (wie heute: Banner wartet, solange Dialog/Pause offen).
- Gründung, Einzug, Stufenaufstieg nutzen dasselbe Banner mit anderer Kopfzeile („STADT GEGRÜNDET", „GUSTAV ZIEHT EIN").

### 5.2 Stufenaufstieg als Zeremonie
Die Stufe steigt heute still im Stadt-Tab. Neu (≈ 4 s, auf jedem Peer in der Stadt):
1. Alle fertigen Gebäude **blitzen nacheinander auf**, von der Hütte nach außen (Verzögerung nach Abstand) – ein Lichtlauf durch die ganze Stadt.
2. Von der Hütte geht eine **große Welle** (nur Optik, räumt nichts) bis zum Rand des Lichtgebiets, der Lichtrand springt sichtbar etwas nach außen, falls die Stufe Reichweite gibt.
3. Glocke, Banner mit „DORF" in großer Schrift und darunter **was neu ist**: „NEU: SCHMIEDE · 2 LICHTPFOSTEN MEHR · BANNER AM DACH".
4. Die Hütten-Banner rollen sich herab (vorhanden als Idee in `town_ausbau.md` A2), Siedler jubeln (Sprechblasen aus ihren `barks`, Platzhalter).

Dafür bekommen die Stufen in `town.json` ein Feld `unlocks` (Liste von Teil-IDs und Texten), das Menü (1.1) und Banner lesen. **Jede Stufe muss etwas Sichtbares freischalten**, sonst ist sie keine. Vorschlag:

| Stufe | Wert | Schaltet frei |
|---|---|---|
| RASTPLATZ | 0 | Lichtpfosten, Zaun, Platten, Bank |
| WEILER | 25 | Vorratslager, Werkstatt, Standarte, Questtafel |
| DORF | 70 | Schmiede, Acker, +2 Lichtpfosten-Limit, Wappen frei wählbar |
| FLECKEN | 150 | (Haken: Brunnen, Marktstand – Handel, Abschnitt 6) |
| STADT | 300 | (Haken: Handelskontor, Stadttor) |

### 5.3 Stadt-Identität: Farbe und Wappen
Grundlage für das Banner **und** für spätere fremde Städte (Abschnitt 6).
- `TownManager` bekommt `identity = {color, emblem}` (gespeichert, Snapshot, Host entscheidet, `_rpc_identity`). Wahl im STADT-Tab neben dem Namen: 8 Farben (aus der Spielpalette: Teal, Weinrot, Nachtblau, Moosgrün, Bernstein, Lila, Knochenweiß, Glut) und 12 Wappen-Glyphen (16 × 16 Pixelzeichen: Laterne, Glimmkappe, Krähe, Fuchs, Tanne, Mond, Hammer, Ähre, Fisch, Schlüssel, Auge, Knospe) aus einem kleinen Generator `tools/art_emblems.py`.
- Benutzt von: Stadtbanner, Hütten-Banner, Standarte `banner_post`, Seitenbanner von Lager/Werkstatt (Palettentausch im Shader: die Tuchfarbe ist eine feste Indexfarbe im Bild, `banner_tint.gdshader` ersetzt sie), Kartensymbol der Stadt.

## 6. Grundlagen für später: Handel, andere Städte, andere Spieler

Nicht bauen, nur **nichts verbauen**. Was jetzt bewusst so gemacht wird:
- **Identität gehört der Stadt, nicht der Welt**: Name, Farbe, Wappen, Gründungstag, Gründer (Peer-ID → Spielername) liegen in einem Block `identity` in `export_state`. Eine zweite Stadt ist später „ein zweiter Block", nicht ein Umbau aller Banner.
- **Keine neuen Singleton-Annahmen**: Alles Neue fragt `TownManager`/Gruppe `town` nach „der Stadt unter Position X" über eine Funktion `town_at(pos) -> TownManager` (heute: die eine Stadt, wenn `light_depth(pos) > 0`, sonst null). Banner, Welle, Menü benutzen nur diese Funktion. Der spätere Umbau auf mehrere Städte (mehrere `TownManager`-Knoten unter einem `Towns`-Knoten, je Stadt ein eigenes Lichtgebiet, eigene Gründerin) ändert dann eine Funktion statt zwanzig Stellen.
- **Fremde Stadt betreten** = dasselbe Banner in der Farbe der fremden Stadt, Kopfzeile „GLIMMRAST · STADT VON MIRA". Das ist der Grund, warum 5.1 und 5.3 jetzt gebaut werden.
- **Handel** braucht später: Warenwerte (`items.json` hat Preise in `shops.json`, ein zentraler `value` fehlt), ein Gebäude (Marktstand/Kontor, Stufe FLECKEN/STADT oben als Haken), Karawanen/Wege zwischen Städten (Trampelwege-Router `TownWays` lässt sich auf lange Strecken nicht direkt übertragen). Alles später, eigenes Konzept.
- **Wem gehört was** in einer Welt mit mehreren Spielerstädten (Baurecht nur im eigenen Licht, Gäste dürfen anpacken aber nicht abreißen): Entscheidung später; die Prüfung liegt ohnehin zentral in `check_place` / `request_demolish` und bekommt dort ein Rechte-Feld.

## 7. Ton
`py -3 tools/audio_town.py` (neu, synthetisierte Platzhalter wie alle anderen): `stone_set` (Grundstein), `material_land`, `snap_tick`, `hammer_build_a-c` (heller als die Hütten-Hämmer), `milestone`, `part_roof` / `part_glass` / `part_cloth`, `consecrate_hit`, `consecrate_bell`, `wave`, `uproot_a-c`, `light_flood`, `town_motif` (Betreten), `level_bells`, `menu_card_in`, `menu_card_flip`.

## 8. Reihenfolge

Jeder Schritt einzeln spielbar und testbar; bestehende Tests (`test_town_rules`, `test_town`, `test_town_story`, `test_town_network`, `test_town_jump`) bleiben grün.

1. **Lichtweihe + Druckwelle** (Abschnitt 4): größter Effekt pro Aufwand, der Moment, den du beschrieben hast. `wave` in town.json, `town_soft_cells_circle`, `_rpc_done` mit Zellen, `TownConsecration`, `town_wave.gdshader`, Ertrag ins Lager (falls gewünscht). Test: Welle räumt nur weiche Props im Kreis und im Licht, Bäume bleiben, `cleared` gespeichert, Netzwerk-Peer sieht dieselben Zellen verschwinden.
2. **Stadtbanner + Identität** (5.1, 5.3): Banner-Stoff, Wappen-Generator, Farbwahl im STADT-Tab, `town_at`.
3. **Baumenü „Bauplan"** (Abschnitt 1): Karten, gesperrte Silhouetten, große Karte mit Mini-Bau, Stadt-Leiste mit Vorschau des Zugewinns; Bauplan-Vorschau in der Welt mit Räum-Markierung und neuem Lichtkreis.
4. **Grundstein + Baustelle** (2, 3.2): Grundstein, fliegendes Material, Gerüst, Meilensteine, Teil-Abschlüsse.
5. **Anpacken** (3.1): E halten, Hammer in der Hand, Pixel-Schwall, Host-Gewichtung.
6. **Stufen-Zeremonie + `unlocks`** (5.2).
7. Doku: `docs/town.md` nachziehen, CLAUDE.md-Eintrag kürzen statt verlängern.

Vorschau-Werkzeug: `tools/preview_town.tscn` bekommt `--consecrate=<piece>` (Aufnahme mehrerer Zeitpunkte der Lichtweihe) und `--menu` für den neuen Bauplan; Kunst macht der Hauptagent selbst.

## 9. Offene Entscheidungen

1. **Ertrag der Druckwelle**: gibt das Entwurzelte etwas ins Stadtlager (Vorschlag: ⅓ des Sammel-Ertrags), oder ist es reine Räumung?
2. **Anpacken**: Anwesenheit baut weiter allein (Vorschlag, niemand wird bestraft) oder *nur* noch Anpacken baut?
3. **Wellenradius**: die Werte in 4.1 sind ein Vorschlag. Größer = sauberere Stadt, aber weniger Wildwuchs-Charme zwischen den Häusern.
4. **Banner beim Betreten**: einmal pro Tag + nach 3 Minuten draußen, oder jedes Mal?
5. **Stufen-Freischaltungen**: Tabelle 5.2 passt, oder sollen manche Teile (Schmiede) weiter an Bewohnern statt an der Stufe hängen? (Heute: `needs_resident`; beides gleichzeitig ist möglich.)

## 10. Gebaut (2026-11-13)

Entscheidungen für die offenen Punkte aus 9: Druckwelle gibt Ertrag ins Lager (ein Wurf des Sammel-/Ernteertrags je Pflanze), Anwesenheit baut weiter (Anpacken zählt dreifach), Banner beim Betreten einmal am Tag oder nach 3 Minuten draußen, Wellenradien wie unten, Freischaltungen bleiben an Bewohnern; jede Stufe bringt stattdessen **mehr Licht** (`levels[].light`, 1.0 / 1.08 / 1.16 / 1.24 / 1.32, `TownManager.light_grow()` auf alle `circles()`/`lit_circles()`).

**Schritt 1 – Lichtweihe, Druckwelle, Gebäudelicht**
- `town.json` Teile: `wave` = px über die Mauern hinaus (`TownManager.wave_radius` = `wave` + halbe Fußbreite: Pfosten 40, Bank/Standarte 24, Lager 64, Werkstatt 72, Tafel 40, Schmiede 80; Zaun/Platte/Feld 0), `aura` {color, radius, energy} = breites weiches Nachtlicht um Gebäude (Lager, Werkstatt, Tafel, Schmiede); deren `reach` ist größer (72/96/56/104).
- Host beim Fertigwerden: `_host_wave` → `WorldLevel.town_wave_cells` (weiche Props + jede kleine Pflanze `Bush`, nur im Licht inkl. des neuen Kreises) → `town_wave_yield` ins Stadtlager → `_rpc_wave(id, cells, gains)` vor `_rpc_done` (gleicher Kanal). Jeder Peer: `WorldLevel.town_uproot` (Props sofort aus den Tabellen, Bild springt zeitversetzt mit dem Ring heraus, platzt in eigenen Farben, Ton), `cleared` gespeichert.
- `TownConsecration` (src/fx): Einschlag + Glocke, Ring (dunkles gepresstes Band + Erdwall, weltbeleuchtet; heller Saum teal/gold, additiv), Staub, Bäume schwanken (`_shake`, Nadelregen), Lichtflut bis `reach`, Name + „+N WERT“ steigen auf, Erträge fliegen zum Vorratslager. `TownStructure._finish_fx`: Seilrahmen fliegt in Splittern weg, Licht/Aura/Glow blitzen auf.
**Schritt 2 – Banner, Identität, Stufen-Zeremonie**
- `TownBanner` neu: Stoffbanner rollt von einem Ast herab (Stadtfarbe, Goldborte, Schwalbenschwanz, Falten, Wind in ganzen Pixeln), Wappen, Titel, Kopfzeile, Unterzeile; wartet bei Dialog/Pause; `show_text` = dunkle Variante für die Nacht. `TownManager.town_banner(info)`.
- `TownEmblems` (src/ui): 8 Farben, 12 Wappen-Glyphen. `look_color`/`look_emblem` (Speichern `look`, `request_look`/`_rpc_look_state`), STADT-Tab FARBE/WAPPEN mit Farbfeld und Wappenbild.
- Betreten: Banner mit Name, Stufe, Einwohner, Tag + Motiv; Lichtrand-Ring um sie (`_greet_light`), Bauten in Sicht blitzen (`TownStructure.flare`). Gründung/Einzug nutzen das Banner. Stufe (`event level_up`, 2,4 s verzögert): Bauten blitzen von der Hütte nach außen, Lichtring bis zum Rand, Glocken, großes Banner mit `levels[].gift`.
**Schritt 3 – Bauplan, Grundstein, Baustelle, Anpacken**
- `BuildMenu`: Karten 40×50 mit echtem Bild (ganzzahlige Bruch-Skalierung `_fit`), Ziffer, Punkt (teal bereit / rot Material fehlt), gesperrt = violetter Bauplan (`blueprint.gdshader`) mit X; Karten werden ausgeteilt (Ton). Große Karte: Bild baut sich im Loop auf (`build_preview.gdshader`), Name, Grund/Info, Bauzeit, LICHT n, +WERT, RÄUMT AUF, Kosten-Chips. Stadt-Leiste über dem Ast: Stufe + Wert-Ranke, Zugewinn des Teils in Gold („DIESES TEIL MACHT EUCH ZUM …“).
- `BuildMode`: Geist = Bauplan-Shader (teal / rot zitternd), neuer Lichtkreis als gestrichelter Goldring, was die Welle räumt hat weiße Ringe und zittert, Einrast-Tick.
- `TownStructure`: Grundstein (`lay_foundation`, fällt, Staub, Drahtgitter-Blitz `flash` im Glow-Shader, Material fliegt vom nächsten Spieler ein, Pflöcke wachsen), Gerüst (`_draw_scaffold`), Meilensteine 25/50/75 %, fertige Teile (`_part_done`), Fortschritt über der Baustelle (nur in der Nähe, „X3“ beim Anpacken), Hammer `hammer_build_*`.
- Anpacken: E an der Baustelle (`ANPACKEN`, Reichweite +16 px) → `TownManager.lend_hand`: Ellie spielt den Pflück-Clip in Schleife (anfassen, setzen), jeder Griff → `_rpc_hand` → Host zählt sie 1,6 s lang dreifach (`_hand_weight`), `_rpc_hand_fx` lässt auf allen Peers Licht aus ihren Händen in den Bau fliegen. Bewegung, Entfernung oder fertige Baustelle beenden es.
- FERTIGE STADT (`debug_build_all`) baut still (`_quiet`).

Ton: `python3 tools/audio_town_build.py`. Blick: `Godot --rendering-driver opengl3 --path . tools/preview_town_build.tscn -- --dir=/abs [--piece=stockpile] [--times=..] [--night] [--mode=done|site|menu|banner|level]`.

**Nicht gebaut:** Banner-Teile in der Welt (Standarte, Hüttenbanner, Seitenbanner) in Stadtfarbe (Paletten-Shader), eigene Bauanimation für Ellie (sie nutzt den Pflück-Clip), Siedler jubeln bei der Stufe, Verzerrung des Bodens an der Welle, `town_at(pos)` (es gibt erst eine Stadt), Handel.
