# Die Stadt – Konzept und Stand

Status: **gebaut und getestet** (Abschnitt 9). Dieses Dokument hält die Entscheidungen fest, an denen sich jede Erweiterung (Felder, weitere Berufe, Handel) messen lässt.

## 1. Vision

Aus der reparierten Hütte wird eine Siedlung. Die Spielerin (und bis zu drei Mitspieler) bauen **frei** auf der Welt: überall dort, wo Licht hinfällt. Siedler kommen zum Licht, ziehen in Werkstätten und Läden ein, arbeiten dort, werden Freunde und schalten Rezepte frei. Später handelt die Stadt mit fremden Siedlungen. Alles ist ein einziges, gemeinsames Projekt der Gruppe; allein spielt man dasselbe, nur langsamer.

Vier Säulen:

1. **Licht ist Land.** Gebaut wird nur im Lichtkreis der Stadt. Die Hütte ist der erste Kreis, jeder Lichtpfosten (später auch Laternenhäuser, Schmieden, Torbögen) trägt ihn weiter. Die Stadt wächst organisch an ihrem Rand, nicht in einem Rechteck. Das passt zu „Licht ist Sicherheit“ der Mine und zum Nachtthema des Spiels.
2. **Frei, nicht gerastert.** Teile stehen auf einem feinen 8-px-Raster (Pfade 16 px), gespiegelt, an jeder legalen Stelle. Kein Bauplatz-Zwang. Bäume und Felsen bleiben im Weg, bis man sie fällt oder abbaut; Büsche, Gras, Pilze und Kiesel räumt das Fundament selbst.
3. **Gemeinsam bauen.** Eine Baustelle wächst nur, solange jemand daneben „Hand anlegt“. Zwei Spielerinnen bauen anderthalbmal so schnell, Siedler zählen mit. So lohnt sich die Gruppe, und es gibt nie „Warten auf einen Timer“ ohne Anwesenheit.
4. **Eine Stadt, ein Zustand.** Die Stadt gehört der Welt (Host), nicht einer Person. Jeder sieht dieselben Bauten, dasselbe Lager, dieselben Bewohner. Sie gilt automatisch als die eigene, sobald die Hütte renoviert ist (Gründung).

Recherche, die in den Entwurf einfloss: Co-op-Basen scheitern, wenn jeder seinen eigenen Haufen baut (deshalb eine gemeinsame Stadt, ein gemeinsames Lager); starre Claim-Radien frustrieren (deshalb wächst das Gebiet mit jedem Licht); Siedler kommen, wenn der Ort einladend wirkt (Lichtpfosten und Werkstatt locken Gustav); Platzierung folgt dem Muster „Client zeigt Vorschau, Server prüft erneut“.

## 2. Regeln

### Gründung
`TownManager.request_found()` (Host entscheidet) läuft von selbst, sobald das Quest-Flag `rebuild_done` des lokalen Spielers gesetzt ist, auch beim Laden alter Spielstände. Mitte = Fuß der Hütte; die Hütte wird als Struktur 0 „Haus“ eingetragen (nicht abreißbar, Lichtradius 11 Tiles). Der Name startet als „Glimmrast“ und lässt sich im Stadt-Tab aus einer Liste wählen. Ein Banner „STADT GEGRÜNDET“ erscheint.

### Lichtgebiet
Jedes **fertige** Teil mit `reach` (px) trägt einen Kreis. Die Vereinigung ist das Baugebiet. Ein neues Teil muss mit seinem Fußpunkt (Mitte der Unterkante) im Gebiet stehen; Lichtpfosten dürfen am Rand stehen und ziehen es nach. Wird ein Pfosten abgerissen, bleibt, was schon steht; es kann nur nichts Neues außerhalb entstehen.

### Platzierung (Host prüft, Client zeigt dieselbe Prüfung als Vorschau)
Reihenfolge der Meldungen (`TownManager.check_place`):
1. Stadt gegründet, Teil freigeschaltet (`needs` Gebäude, `level` Stufe), Limit (`max_pieces`), Reichweite des Bauenden (≤ 240 px).
2. Innerhalb des Lichtgebiets.
3. Land, flach, eine Höhenstufe, kein Hang/Rampe, kein Wasser, keine Welt-Kollision (`WorldLevel.town_probe`: Bäume, Felsen, Hütten, Klippen, andere Bauten).
4. Kein anderes Teil überlappt (Datenvergleich der Fußflächen, gilt auch für nicht geladene Teile).
5. **Die Türzone bleibt frei** (`front` [Breite, Tiefe] am Teil: Hütte, Vorratslager, Werkstatt): der Streifen vor der Türkante, wo man steht, arbeitet und hineingeht (Gustavs Arbeitsplatz liegt darin; getestet in `test_town_rules`). Er wird wie die Fußfläche gegen die Welt geprüft (`TÜR ZUGESTELLT`: ein umgestürzter Baumstamm, ein Stamm oder ein Fels direkt vor der Tür; Stämme sind nicht zerstörbar, die Tür wäre für immer zu), und kein Teil darf in der Türzone eines anderen stehen (`VERSPERRT EINE TÜR`) oder die Tür des neuen mit seinem Fuß verbauen. Trittplatten sind Boden und dürfen in die Türzone. Weiche Props in der Türzone werden mit der Fußfläche geräumt; der Baumodus zeichnet die Türzone gestrichelt, die der vorhandenen Türen blass.
6. Niemand steht im Fundament (Spieler, Siedler).
7. Material vorhanden: erst Stadtlager, dann Rucksack des Bauenden (`available`).
Weiche Props (Busch, Beerenbusch, Glutbrombeere, Gras, Kiesel, Pilze, gefällte Stümpfe, erschöpfte Felsen) in der Fußfläche werden beim Setzen entfernt und als `cleared` im Stadtzustand gespeichert (Chunks laden sie nicht wieder, `WorldLevel._prepare_thing`).

### Bauen
Setzen zieht das Material sofort ab und legt eine Baustelle an (`g` = Fortschritt 0..1000). Der Host zählt jede Physikframe die Helfer in 100 px Umkreis (lebende Spieler, die nicht in Szenen stecken; Siedler an ihrem Arbeitsplatz). Rate: `1000 / build_seconds · (1 + 0.5 · (Helfer − 1))`, ohne Helfer steht die Baustelle still. Die Baustelle zeigt Seilrahmen und einen Fortschrittsstrich; das Teil wächst von unten nach oben ins Bild; Helfer hämmern hörbar (Klopfen alle 0,9 s, Staub). Fertig → Licht, Funktion, `built(piece, id)`, die Quest setzt `built_<piece>`.
Abriss: Baustelle erstattet 100 %, Fertiges 60 % (aufgerundet) ins Stadtlager; die Hütte bleibt.
**Verbrauchtes im Licht verschwindet:** Ein Strauch, der abgeerntet, ein Baum, der gefällt, ein Fels, der abgebaut, oder ein Kiesel/Pilz, der aufgehoben wurde, und dessen Fuß im Lichtgebiet der Stadt steht, bleibt nicht als Stumpf, Geröll oder nachwachsender Setzling zurück: der Host räumt ihn kurz nach dem Effekt weg (0,9 s, Bäume 5 s wegen des Falls, `WorldLevel._sweep_spent` -> `TownManager.clear_spent`), er steht in `cleared`, wächst nie wieder und wird mit der Stadt gespeichert. Beeren und Blüten wachsen weiter nach, die Pflanze bleibt.

**Das Baumenü** (`BuildMenu`, wächst wie die Hotbar): ein Zweig über der Hotbar, daran hängen die Kategorien als Namensschilder (dieselben wie im Escape-Menü, das offene golden mit Licht darunter; ganz rechts das Schild `X ABRISS`, anklickbar), darunter eine dünnere Ranke mit den Teilen als Anhängern (Zifferntaste, das gewählte hebt sich und glüht, eine Blüte öffnet sich darüber) und daneben ein kleines Papierblatt: Name, Bauzeit, Beschreibung oder (rot) was das Setzen gerade verhindert, Kosten als Material-Chips (rot, wo Lager und Rucksack nicht reichen). Beim Abriss zeigt das Blatt, was zurückkommt. Alles außer Schildern, Anhängern und Blatt ist durchsichtig; liegt das Teil, das gesetzt würde (oder das zum Abriss anvisierte), auf dem Bildschirm hinter dem Menü, wird es blass (30 %), solange die Maus nicht darüber ist. Beim Schließen verschwinden Fußfläche und Lichtring sofort. Die Breite ist in jeder Kategorie gleich (richtet sich nach der größten). Vorschau: `Godot --rendering-driver opengl3 --path . tools/preview_town.tscn -- --capture=/abs.png --ghost --site [--cat=N] [--demolish] [--south] [--night]`.

### Trampelwege
Gebäude mit `paths: true` (Vorratslager, Werkstatt) bekommen beim Setzen **automatisch einen Trampelweg**, der aussehen soll wie von Füßen getreten, nicht wie mit dem Lineal gezogen. Der Host sucht von ihrer Tür (Vorderseite, bei Hindernissen die Seiten und die Rückseite) zur nächsten Tür des Städtchens (Hütte oder anderes Gebäude) und rechnet das in `TownWays` (reine Funktionen, ohne Welt):
- **Gewichtete Suche** (A* auf 8-px-Zellen mit Zellgewicht): festgetretener Boden kostet 1,0, freier Boden 1,4 plus langsames Rauschen (Buckel, feuchte Stellen: der Weg biegt sich), Wände, Stämme und Steine kosten umso mehr, je näher man ihnen kommt (man hält Abstand). Das gibt Verschmelzungen unter etwa 45 Grad wie bei zwei Bächen, nicht im rechten Winkel.
- **Verschmelzen:** trifft der neue Weg auf einen älteren (fertige Wege zählen), endet er dort mit einem kurzen Stück daneben (`joined`, `e: 0`); sonst läuft er bis zur Tür (`e: 1`). Mindestens 12 px lang, bevor er einmünden darf.
- **Formen:** die Zellenkette wird ausgedünnt (Douglas-Peucker 3 px), zweimal abgerundet (Chaikin), alle 6 px neu gesetzt und bekommt eine leise seitliche Schwingung (an den Enden null). Danach wird sie noch einmal gegen Hindernisse und Gelände geprüft, sonst weniger Rundung (4 Stufen, zuletzt die rohe Kette).
- **Bild** (`TownPathArt`, auf jedem Peer gleich aus Linie und Seed): Breite schwankt (Rauschen, ab und zu eine breite Stelle, wo man ausgewichen ist), vor der Tür eine **abgetretene Schürze** (am Ende auch, wenn dort eine Tür ist), fester Kern, Rand aus dünner werdendem Boden (Gras kommt Pixel für Pixel zurück, Dither plus Rauschen), Grasbüschel mitten drin, Schattenrand Nordwest, Lichtrand Südost, Kiesel. Farben des Story-Fußwegs.
Der Weg erscheint, wenn das Gebäude fertig ist (er blendet ein), zählt als Oberfläche `path` und **bleibt**, wenn das Gebäude abgerissen wird. Gespeichert unter `paths` (`s` Gebäude, `p` Punkte, `d` fertig, `e` endet an einer Tür). Test ohne Welt: `tools/test_town_ways.tscn`; Bilder ohne Welt: `Godot --headless --path . --script tools/preview_ways.gd -- /abs/out.png [Maßstab]`.

### Stadtlager
Ein gemeinsamer Vorrat (`stock`, Item → Zahl). Das **Vorratslager** (Gebäude) ist der Ein- und Ausgang: E öffnet das Lagerfenster (alles Material einlagern, je 10 oder alles herausnehmen). Bau- und Rezeptkosten werden zuerst aus dem Lager, dann aus dem Rucksack bezahlt (Rezepte erst aus dem Rucksack). Ohne Lager-Gebäude bleibt es leer.

### Stufe der Stadt
`worth` jedes Teils plus 8 pro Bewohner ergibt den Wert; `data/town.json "levels"` legt die Schwellen fest (Rastplatz, Weiler, Dorf, Flecken, Stadt). Die Stufe schaltet Teile frei und wird im Stadt-Tab gezeigt. Mit den Startteilen erreicht man Stufe 2 (Weiler); die höheren sind für die kommenden Gebäude da.

### Siedler
Siedler sind in `data/settlers.json` beschrieben (Name, Rolle, Gebäude, Ankunftsbedingung, Tagesplan, Dialoge). **Sie sind keine Netzwerkobjekte:** ihre Position ist eine reine Funktion von Tageszeit, Plan und Gebäudeposition und wird auf jedem Peer gleich berechnet. So gibt es nichts zu synchronisieren, kein Auseinanderlaufen und keine Pfadsuche in der Stadt. Zustand pro Siedler (Host, gespeichert): `trust` (0..100), `talked` (letzter Tag mit Gespräch). Sie kommen, sobald ihre Bedingung erfüllt ist (Gebäude seit `delay` Sekunden fertig), von einer Himmelsrichtung her zum Licht, laufen zu ihrem Arbeitsplatz und bleiben. Tagsüber arbeiten sie (hämmernde Geräusche im Takt des Arbeitsclips), abends stehen sie am Feuer der Hütte, nachts schlafen sie (unsichtbar).
**Tagesplan Gustav:** Werkbank 06:58–13:26, Mittagspause am Feuer bis 14:24, Werkbank bis 18:14, Abend am Feuer bis 21:07 (Nacht beginnt 20:00), dann schläft er im Haus. **Leben um die Werkstatt:** Schornsteinrauch (`smoke` am Teil, folgt dem Wind) steigt nur, solange ihr Siedler wach ist; das Schmiedelicht sinkt ohne ihn auf Glut. **Tiere:** Wildtiere im Lichtgebiet der Stadt sind an Menschen gewöhnt (`TownManager.calm_at`: 70 % der üblichen Scheu vor Spielern bei Hasen, Vögeln, Rehen und Co.; Bären und Raubtiere unverändert).
**Siedler gehen wie Menschen, nicht wie ein `lerp`:** jeder Wechsel des Ortes (und die Ankunft) ist eine Route (`TownManager.walk_route`, gerechnet von `TownWays` mit `join = false`): um alle Teile (Hütte, Werkstatt, Zäune, Lager) und alles herum, was der Boden verbietet (Stämme, Felsen, Wasser, Hänge), und auf den Trampelwegen, wo sie in die richtige Richtung führen (festgetretener Boden kostet weniger). Sie gehen gleichmäßig (34 px/s, ein langer Weg wird im Wechselfenster schneller) ab dem Moment, in dem der Plan wechselt, und stehen dann. Die Position bleibt eine reine Funktion von Uhr, Plan und Route, nichts wird synchronisiert; Routen und Standpunkte sind pro Peer zwischengespeichert (neu bei Änderung der Stadt und alle 20 s, weil Props mit den Chunks laden; gleiche Eingaben geben dieselbe Route). **Standpunkt** (`stand_point`): ein Platz im Gebäude (das Bett hinter der Werkstattwand) ist die Tür des Gebäudes, der Siedler geht hinein (er verschwindet, wenn er angekommen ist) und kommt dort wieder heraus; ein blockierter Platz (Baumstamm, Zaun) wird auf den nächsten freien Punkt innerhalb von etwa 48 px gelegt. Findet sich keine Route (eingemauert), steht er einfach am Ziel, statt durch Wände zu schweben.
Vertrauen wächst durch ein Gespräch pro Tag (+10, bis 100) und schaltet Rezepte und Dialogzeilen frei. Bewohner arbeiten für die Stadt (`produces`): Gustav sägt jede Spielstunde zwei Bretter aus dem Lagerholz.

**Gustav** (`docs/characters/gustav.md`) ist der erste Siedler: Zimmermann, Stellmacher und Allround-Bauer, laut, herzlich, verpeilt, Ende 40. Er kommt, wenn die Werkstatt steht. Texte (`data/dialogue.json`: `town_intro`, `gustav_hello`, `gustav_talk_a..c`, Barks in `settlers.json`) sind Platzhalter für den Dialog-Writer (`docs/prompts/dialogue_writer.md`).

### Handwerk, Aufträge und Handel (`ShopWindow`, `data/shops.json`)
Jede Person-mit-Ort, bei der man etwas macht, kauft oder verkauft, ist **ein Eintrag in `data/shops.json`** (`title`, `npc`, `role` des Gebäudes, `reach`, `tabs`, `buy`, `sell`, `lines`); Gustavs Werkbank (`gustav_bench`) ist der erste, Schmiede, Küche und Markt benutzen dasselbe. Ein Tab hat eine `kind`:
- `craft`: was man **selbst** macht (Rezepte mit `by: "self"`): kurzer Balken, dann tauscht der Host Material gegen das Ergebnis.
- `order`: was **nur die Person** machen kann (`by: "npc"`, `work` Sekunden, `trust`). Das Material wird übergeben, die Person arbeitet daran, **solange sie an ihrer Bank steht** (nachts, in der Pause oder beim Gang zum Feuer ruht der Auftrag), das fertige Stück liegt auf der Bank, bis jemand es abholt. Die Warteliste (3 Plätze) gehört der Stadt, nicht einem Spieler, und wird mit der Stadt gespeichert (`orders`: `{r, left, total, done}`). Host: `request_order` / `request_collect` / `_work_orders`; ein fertiger Auftrag meldet sich mit dem Stadtbanner.
- `buy` / `sell`: Preisliste in Kupfer (`item`, `price`, optional `trust`); der Host prüft Nähe, Vertrauen, Geld, Platz im Rucksack (`request_trade`).
Das Fenster ist **`BoardWindow`** (gemeinsame Bühne aller Stadtfenster, auch `StockWindow`): die Kamera zoomt pixelrein auf 2 und rahmt die Person bzw. das Lager **links**, das Brett hängt rechts an einem Ast mit Blättern (`VineStyle`), die Reiter hängen als Namensschilder daran (wie im Escape-Menü), Zeilen sind Gegenstandsfelder mit Seltenheitsring (`ItemSlot`-Look), die Karte beim Überfahren ist `ItemTooltip`, Münzen sind die der `PurseVine`. Die Person antwortet in einer Sprechblase über dem Kopf (Zeilen in `lines`, Platzhalter für den Dialog-Writer). Steuerung: W S / Pfeile wählen, A D / Schultertasten / Klick wechseln den Reiter, E / A tut, Shift (Sprint) wirkt auf den ganzen Stapel, Mausrad scrollt (beliebig viele Zeilen), Esc geht zurück, die Kamera schwenkt zurück. Neues Fenster = Unterklasse mit `_setup_board / _rebuild / _detail / _buttons / _press`.
Das **Stadtlager** hat zwei Reiter: LAGER (E nimmt 10, Shift alles) und RUCKSACK (E lagert 10 ein: Material und Essen; „ALLES MATERIAL“).
Rezepte (`data/recipes.json`): Station, Zutaten, Ergebnis, `by`, `seconds` (selbst) bzw. `work` (Auftrag), Mindestvertrauen, `npc`, `once`. Neue Items: `plank` (Brett), `rope` (Seil). Preise und Zeilen sind Platzhalter.

## 3. Steuerung (Baumodus, Taste B)

| Aktion | Maus/Tastatur | Gamepad |
|---|---|---|
| Baumodus an/aus | B | D-Pad hoch |
| Teil wählen | Zahlen 1–8, Mausrad | D-Pad links/rechts |
| Kategorie | V | linke Schulter |
| Setzen (halten: Reihen von Zäunen und Platten) | linke Maustaste | A |
| Spiegeln | R | B |
| Abriss-Werkzeug an/aus | X | D-Pad runter |
| Verlassen | Escape / rechte Maustaste / B (Taste) | X |

Im Baumodus schwingt die linke Taste kein Schwert und die Zahlen wählen keine Schnellleiste (`InputManager.build_open`). Die Spielerin läuft weiter, E benutzt weiter. Gamepad: die Vorschau steht 40 px vor ihr in Blickrichtung.
Vorschau: durchscheinendes Teil, türkis = gültig, rot = ungültig (mit Grund auf der Karte), Fußfläche als Rahmen, Rand des Lichtgebiets als wandernde türkise Punkte, Kosten mit Zähler (rot wenn es fehlt). Auch über die STADT-Seite im Escape-Menü: BAUEN / ABREISSEN.

## 4. Escape-Menü: STADT

Der Tab STADT ersetzt FÄHIGKEITEN (der Skillgraph bleibt auf F / Start und hat einen Button „FÄHIGKEITEN“ auf der Einstellungsseite). Seite: Name, Stufe, Wert bis zur nächsten Stufe, Einwohner, Bauten (fertig + im Bau), Lichtreichweite, Gründungstag; VERWALTUNG: Bauen, Abreißen, Namen wählen (Pfeile oder Klick); rechts: Lager, Bewohner mit Vertrauen, Bauten nach Art. Ohne Stadt: „NOCH KEINE STADT“.

## 5. Datenformate

`data/town.json`
```
"name": {"default", "choices": [...]}
"limits": {"max_pieces", "build_reach", "helper_radius", "view_radius", "unview_radius", "refund_done"}
"soft_kinds": [...]   "levels": [{"id", "name", "worth"}]   "resident_worth"   "categories": [{"id", "name"}]
"pieces": id -> {name, category, texture, frame [w,h], feet (row), foot [w,h], snap, cost {item: n}, build_seconds, reach (px light), worth,
                 level, needs (piece id), walk (true: no collider), pad, glow, light {color, radius, energy, at, flicker}, role ("stock" | "craft"),
                 paths (true: gets a trampled way), front [w, d] (the free ground in front of the door), surface, info}
```
`data/settlers.json` (id → name, title, art, role, home, arrive {needs, delay, angle, distance}, spots {work, fire, rest}, schedule [[from, to, spot]], produces, talk [{trust, dialogue}], barks), `data/recipes.json`, Quests `town_start` in `data/quests.json`, Dialoge in `data/dialogue.json`.

## 6. Netzwerk und Speichern

`TownManager` (Knoten `Town` unter `WorldLevel`, Gruppe `town`) hält den Zustand auf jedem Peer; der Host entscheidet.
- Client → Host: `_rpc_place`, `_rpc_demolish`, `_rpc_stock_request`, `_rpc_craft`, `_rpc_name`, `_rpc_talk`, `_rpc_found`.
- Host → alle: `_rpc_added`, `_rpc_removed`, `_rpc_progress` (gebündelt, 4/s, unzuverlässig), `_rpc_done`, `_rpc_way_added`, `_rpc_stock_state`, `_rpc_resident`, `_rpc_name_state`, `_rpc_snapshot` für Beitretende (bei `peer_connected`).
- Gespeichert wird unter `"town"` in `save.json` (`SaveGame`, `export_state` / `import_state`). `TownStructure`-Knoten und Wege-Sprites sind reine Ansicht; Strukturen werden pro Peer nahe dem lokalen Spieler geladen (700 px) und wieder entladen.

## 7. Teile

| Teil | Zweck | Fuß (px) | Kosten |
|---|---|---|---|
| Lichtpfosten | trägt das Licht 7 Tiles weiter, teal Nachtlicht | 12×8 | 3 Holz, 2 Glimmkappen |
| Zaunstück | Grenzen, Gehege | 24×6 | 1 Holz |
| Bank | Sitzplatz, Wert | 32×10 | 3 Holz |
| Trittplatte | Wege (begehbar, 16-px-Raster, Oberfläche Stein) | 16×16 | 1 Stein |
| Vorratslager | Stadtlager, Weg zur Hütte | 64×28 | 14 Holz, 4 Stein |
| Werkstatt | Werkbank, Schmiede; Gustav arbeitet hier; Weg | 96×40 | 24 Holz, 10 Stein, 4 Faser |

Alle Teile sind echte gerenderte Ellipsoid-Modelle in den Farben der renovierten Hütte (`python3 tools/art_town.py [preview.png]` → `assets/town/<teil>.png`, `_glow` mit nur den leuchtenden Pixeln, `_pad` als festgetretene Erde unter großen Teilen; plus die Item-Symbole `plank.png`, `rope.png`). Das Modell steht auf der **Vorderkante** der Fußfläche (z von −Tiefe bis 0), 1 px Bodentiefe sind 2,5 Modelleinheiten.

## 8. Art-Vertrag für Siedler (Figuren macht ein eigener Agent)

Ein Siedler braucht nur diese Dateien; bis sie da sind, steht eine schlichte Platzhalterfigur (`Settler._draw`) und im Dialog erscheint kein Porträt:
- `assets/characters/<art>.png` (`art` aus `settlers.json`, hier `gustav`): 8 Zeilen = Blickrichtungen E SE S SW W NW N NE (wie Spielerin und Ritter), eine Spalte pro Frame. Dazu optional `<art>_glow.png` gleicher Aufbau mit nur den leuchtenden Pixeln (ungeschattet gezeichnet).
- `data/<art>_rig.json`: `{"frame": [w, h], "feet": [x, y], "frames": N, "height": px Figurenhöhe (optional, für das E-Symbol), "clips": {"idle": {"start", "count", "fps", "loop"}, "walk": {...}, "work": {..., "strike": 3}}}`. `work` ist der Hammer-/Sägetakt am Bank (Blick nach Norden); `strike` ist der Frame, in dem der Hammer trifft (der Ton kommt dann).
- `assets/ui/portrait_gustav.png`: 103×153, Kopf bis Hüfte, Dreiviertelblick nach rechts (`docs/dialogue_art.md`). `DialogueBox.LATE_PORTRAITS` lädt es, sobald die Datei existiert (auch für den Sprecher „FREMDER“, der bis zum Flag `gustav_joined` als Silhouette erscheint).

## 9. Stand der Umsetzung

Gebaut: Gründung, Lichtgebiet, freie Platzierung mit Rasterschnapp und Spiegeln, Baustellen mit gemeinsamem Bauen, Abriss mit Erstattung, Stadtlager, Trampelwege, Räumen weicher Props, Stufen, Siedler-System (Zuzug, Tagesplan, Vertrauen, Produktion), Handwerk (Werkbank-Fenster, sechs Rezepte), Baumodus mit Karte, STADT-Tab, Speichern, Beitreten, Story-Quest `town_start` (Valdric am Morgen, Lichtpfosten, Werkstatt, Gustav zieht ein), Lektionskarte, Banner.

Offen (nicht gebaut):
- **Felder und Pflanzen:** `category: "field"` mit Bodenmuster statt Sprite; Ernte über das Prop-System.
- **Weitere Bewohner** (Händler, Köchin, Bergmann, Heilerin), Geschenke (`likes`).
- **Nachtschutz:** Schattenwesen scheuen das Lichtgebiet (die Radien sind in den Daten, die Gegnerseite ist nicht entworfen).
- **Handel mit fremden Siedlungen:** Wege über `tools/bake_ground.py`, Preise in `data/trade.json`, Händler als Rolle, Karawanen.
- **Rollen und Rechte** für Gruppen; Siedlerfiguren, -porträts und Feinschliff der Texte (eigene Agenten).

## 10. Prüfungen

- `Godot --headless --path . tools/test_town_rules.tscn` – Daten und reine Regeln (Katalog, Footprints, Raster, Gebiet, Stufen, Erstattung, Zustand ↔ JSON).
- `Godot --headless --path . --fixed-fps 60 tools/test_town.tscn` – ganze Welt: gründen, bauen, Helfer, Licht, Räumen, Abriss, Lager, Wege, Werkstatt, Gustav (Ankunft, Tag, Nacht), Vertrauen, Handwerk, Produktion, Baumodus, STADT-Tab, Fenster, Speichern.
- `Godot --headless --path . --fixed-fps 60 tools/test_town_story.tscn` – die Quest `town_start` von der Gründung bis zum Einzug.
- Netzwerk: `Godot --headless --path . tools/test_town_network.tscn -- --server`, dann ein zweiter Prozess ohne Flag (Port 17896): später Beitritt, Bestellen und Bezahlen durch den Client, Fortschritt, Umbenennen, Abriss.
- (`test_town` prüft auch Lager- und Werkbankfenster, Aufträge, Kauf und Verkauf.)
- `Godot --headless --path . tools/test_town_ways.tscn` – Wegsuche und Bild ohne Welt (auch der Gang eines Menschen: Hindernis, Trampelweg).
- Echte Bilder: `Godot --path . --rendering-driver opengl3 --fixed-fps 60 tools/preview_town.tscn -- --capture=/abs/datei.png [--night] [--ghost] [--site] [--tab] [--craft] [--stock] [--craft --tab=0..3] [--walk --at=0.0025]` (`--walk`: Gustav auf dem Weg von der Werkbank zum Feuer, `--at` = Tagesbruchteil nach dem Planwechsel).


### Entwickler: FERTIGE STADT
Escape-Menü → ENTWICKLER → STORY-SPRUNG → FERTIGE STADT (`WorldLevel.debug_jump_town`, nur solo): alles davor gilt als erledigt, die Stadt steht mit je einem Teil des Katalogs (2 Lichtpfosten, 4 Zäune, 6 Platten), Gustav ist zu Hause an der Werkbank, die Quest steht bei „EIN FREMDER KOMMT ZUM LICHT“. Test `tools/test_town_jump.tscn`.

**Die erste Nacht der Stadt-Quest:** Der Schritt `town_night` („RUHE DICH AUS, BIS ES MORGEN WIRD“) lässt sie das Bett der Hütte noch einmal benutzen (`Interior` „BedRest“ → `start_sleep(player, true)` → `SleepScene` / `WakeScene` mit `rest`): schwarz, geheilt, die Uhr springt auf 08:00 (der Sonnenaufgang setzt `town_morning`), sie wacht im Bett auf; keine Gedanken, keine Flags, der Ritter bleibt, wo er ist.

### Aufbau-Animation und Lichtpfosten (neu gestaltet)
- **Aufbau Pixel für Pixel:** Eine Baustelle wächst nicht mehr als Wischer von unten, sondern fügt sich zusammen (`assets/shaders/build_pixels.gdshader` + `.gdshaderinc`, `build_pixels_glow.gdshader`; `TownStructure._add_layer` / `_update_build`). Jeder deckende Pixel des Bildes hat eine Reihenfolge (unten zuerst, aber per Hash gestreut); erreicht der Bau ihn, fällt er aus bis zu 7 Reihen darüber an seinen Platz und leuchtet dabei teal-weiß; was noch fehlt, zeigt sich als punktierter Bauplan (flackernde teal Punkte, dichter an der Baufront). Der gezeigte Fortschritt folgt dem echten weich (`_shown`); ist das Teil fertig, verschwinden die Shader (Teile mit Wind behalten ihren). Gilt für alle Teile. Daten: `window` [von, bis] = welchen Abschnitt des Baus dieses Bild macht.
- **Teile am Bauwerk** (`parts` in `data/town.json`): eigenständige Bilder (Textur, Frame, `at` = linke obere Ecke im Frame, `window`, optional `sway` {pivot, amount, flutter} = hängt im Wind in ganzen Pixeln, `glow` {frames, fps} = ungelittener Frame-Streifen, `fireflies` = die nächtlichen Glühwürmchen sammeln sich dort). `anim` {frames, fps} lässt den Glow-Streifen des Bauwerks laufen; `motes` {at, color} = kleine Lichtfunken, die nachts aufsteigen; `preview` = Bild für Baumenü und Geist (Pfosten samt Laterne).
- **Lichtpfosten:** zwei junge, umeinander gedrehte Stämme in einem Steinhaufen mit Moos und vier Glimmkappen am Fuß, ein Arm, der sich nach rechts über die Laterne krümmt (Rindenhaube mit Knospe), Kette, Käfiglaterne mit Glas und drei Glimmkappen darin, Windspiel aus Glasperlen, Efeu mit leuchtenden Knospen. Das Licht wird durch das Holz getragen: eine violette Ader windet sich den Pfosten hinauf, ein Lichtpuls läuft von Fuß bis Laterne (8 Frames, 6 fps); Kappen und Knospen atmen jede in eigenem Takt; die Laterne schwingt im Wind, die Flamme flackert (8 Frames, 8 fps) mit gepunktetem Hof, Funken steigen nachts auf, die Lichtkugel flackert leicht. Das Bild selbst hat nur trübe Gläser und Adern; das Licht kommt aus den ungelitteten Streifen (tags 30 %, nachts 100 %). Bild: `python3 tools/art_lamp.py [vorschau.png]` (ruft `art_town.py` mit auf), Frame 48x72, Laterne 24x32 bei (24, 16). Vorschau: `... preview_town.tscn -- --capture=/abs.png --site --lamps` (vier Pfosten bei 25/50/75/100 %).
- **Kauffenster:** Name und Tätigkeit der Person stehen groß unten rechts auf der freien Fläche (`BoardWindow._persona`; Name 3x, Tätigkeit 2x), die Reiter hängen oben rechts frei an einem Zweig über der Box.

### Valdric im Alltag der Stadt
Valdric ist ab der Gründung der Stadt ein Bewohner wie Gustav (`data/settlers.json`: `founder`, `counts` false = zählt nicht für Größe und Wert der Stadt, `takes_over` "knight", `actor` "knight"). Der Ritter der Geschichte (`Quarry.knight`, `Adventurer`) wird dabei weggelegt (`WorldLevel.take_knight`, `knight_taken`: `place_knight` tut dann nichts mehr), und ein `Settler` mit der Ritterfigur (`adventurer.png`, `adventurer_rig.json`) läuft von seinem Platz aus weiter; die Quest-Marker folgen ihm weiter (`actor` "knight"). Er ist nie versteckt und immer ansprechbar.
- **Tagesplan** (Zeit als Anteil des Tages): 0,22 Tür (steht) · 0,40 Hütte ausbessern (Hammer-Clip an der Wand links der Tür, mit Hammerschlägen) · 0,52 Feuer (setzt sich auf den Baumstamm, `sit_down` dann `sit`) · 0,57 Schwertübung im Hof (Zyklus `slash_a`, `slash_b`, `flick`, `slash_c` mit Pausen) · 0,70 Wache am Weg (steht, schaut nach Süden) · 0,78 Feuer · 0,88 Nachtwache sitzend am Baumstumpf bis zum Morgen. Wege laufen wie bei allen Siedlern entlang der Trampelwege (`walk_route`).
- **Spots erweitert** (für jeden Siedler nutzbar): `clip`, `enter` (einmal beim Ankommen), `clips` + `pause` (Zyklus), `face`, `sound` "hammer" + `strike`. Nicht schleifende Clips halten ihr letztes Bild.
- **Ansprechen:** E gibt immer genau eine Zeile (Sprechblase unten, `SpeechBox`), die erste des Tages baut Vertrauen auf. Pools (`chat` im Eintrag): `quest` nach aktuellem Quest-Schritt (Gewicht 4), `spot` nach aktuellem Platz (2), `night` nachts (3), `any` (2); nie dieselbe Zeile zweimal hintereinander. **Alle Zeilen sind Platzhalter** für den Dialog-Writer (`docs/prompts/dialogue_writer.md`).
- Test: `tools/test_town_story.tscn` (Tagesplan, Ansprechbarkeit, Zeilen-Vielfalt, Quest-Zeilen), Vorschau: `preview_town.tscn -- --capture=/abs.png --valdric=0.45` (0,45 Hütte, 0,54 Feuer, 0,62 Übung, 0,74 Wache, 0,95 Nacht).

**Reiter-Schilder:** Kauffenster (`BoardWindow`) und Baumenü hängen ihre Schilder jetzt wie das Escape-Menü auf (`VineStyle.tab` / `plate` / `bloom`): schräger Faden vom Zweig, jedes Schild schwingt auf eigenem Takt, fällt mit Überschwingen ein, das offene hebt sich 3 px, wird warm getönt, glüht und trägt eine Blüte auf dem Zweig, ein überfahrenes hebt sich 2 px und glimmt. Das Escape-Menü selbst zeichnet noch mit seinem eigenen Code (gleiche Optik).


## Roofs (shingles)
The roofs of the renewed hut, the stockpile and the workshop use the material `ROOF` (hut_lib) in the 3D model; `hut_lib.roof_pass(arr, seed, moss)` then redraws those pixels in 2D as rows of overlapping shingles (4 px rows, staggered joints, three colour families plum / clay / slate, lit lip on each lower edge, shadow on the row it covers, eave underside, patches of sun-bleach and damp, a little moss, 3 px cast shadow under the eave; the rim keeps the renderer's ink line). Called from `hut_outside.hut_arr` (only when `fresh()`) and `art_town.stockpile/workshop`. Re-run `python3 tools/art_hut_fresh.py` and `python3 tools/art_town.py stockpile workshop`, then `--import`.

### Walls and the lit window of the renewed hut
`hut_lib.wall_depth` shades the wood pixels of the hut front as ambient occlusion (band steps inside each ramp: under the eave, at the foot, in the corners, beside the dark door, plus knots). The window is bigger (`hut_outside.hut_arr`, fresh only): recessed pane, cross of bars, frame, lintel, jutting sill, painted dusty-blue shutters (`SHUT`), a flower box. `hut_lib.window_pass` repaints the glass as a warm gradient (bright at the bottom middle) with a shelf, hanging herbs, a pot and a drawn curtain. `hut_lib.window_spill` writes `fresh/hut_window_light.png`: an additive picture of the lamp light (bloom round the glass, a patch on the ground widening with distance, the bars cast into it). `Hut.set_renewed` adds it as an unlit additive sprite that flickers (`_process`, stronger at night) and enlarges the window's real `NightLight`. Preview: `tools/preview_town.tscn -- --hut [--night] --capture=...`. Stockpile and workshop got a deeper eave shadow (`roof_pass(shadow=7/8)`).
The broken hut (`tools/art_hut.py`) got the same treatment in its own style: the roof is shingled (`roof_pass`, thick moss 0.5 over the 3D moss; the hole and 30 % bare rotten board segments stay), the window keeps its old size and shutter but is repainted by `window_pass(dim=0.14)` (a dimmer glass) and also gets `assets/interior/hut/hut_window_light.png`; `Hut` shows the lamp light for both looks (`_load_spill`). Preview: `--oldhut`.

## Life on the pieces: light, wind, wear, animals (tests: `tools/test_town_critters.tscn`)
- **Forge and lantern light:** data `spill` {texture, forge, base} of a piece is an additive picture of the piece's size (`hut_lib.pool_spill`: bloom + floor pools, written by `art_town.py` as `workshop_spill.png`, `stockpile_spill.png`), drawn unlit by `TownStructure` and breathing with the light; the forge's drops to embers while nobody tends it. `sparks` {at, color} are specks over the forge's mouth while somebody works.
- **Wind:** parts with `sway` hang on the pieces and move in whole pixels with `WorldWind` (build shader): the lanterns of stockpile and workshop, the stockpile's sign (all rendered apart by `art_town.part()`, `INFO` prints their `at` and `frame` for data/town.json) and a teal pennant on each roof (`streamer`, `pole`). The renewed hut has a weathervane (`hut_outside.vane_arr`, `Hut._vane`) that swings round with the wind.
- **Wear:** data `wear` [{texture, days}] are overlay pictures that show once the piece has stood that many days (`structures[id].b` = day it was finished, `TownStructure.age_days()`; old saves count from the founding): the splitting block with chips (stockpile, day 0), crates (2), a firewood stack (4); shavings (workshop, 1), a board stack (3), soot and a coal bucket (6). New stages fade in with a puff of dust. The developer checkpoint backdates every piece by six days. Preview: `--aged`.
- **Gustav's day** has two more spots: `split` (at the stockpile's splitting block: the work clip with a lower-pitched thunk and flying chips, `chips`) and `bench` (beside the first bench; without one the spot falls back to `fallback`, see `Settler.resolve_spot`; a `sit` clip from the art agent is used automatically, until then he stands). Spots may hang on any piece id (`of`). Spot barks: `barks_spot`.
- **Animals:** `RoofPerch` (src/town/roof_perch.gd, group `town_perches`, data `perches` [[x, y, height]] of a piece and the hut) are places birds may land; `CorvidPopulation.choose_perch` knows them like trees. `TownCritters` (host, child `Critters` of `TownManager`): in daylight while somebody is near, one to three crows (sometimes a raven) come in from outside the view and land on the roofs, stay 3-7 minutes, then are freed when unseen; on most nights a fox walks to the stockpile's front, sniffs (ground, listening pause, ground, `WoodlandMammal.visit`), and trots off, or gives up when anybody comes near. Both are spawned by the ordinary populations (`spawn_visitor`), so their caps and rules hold. Dev: `town.critters.debug_visit("crow" | "fox")`, preview `--crow` / `--fox`.
