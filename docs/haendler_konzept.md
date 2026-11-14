# Die Karawane – Konzept „Der fahrende Händler"

Status: **Schritte 1–5 gebaut (2026-11-13)**, siehe Abschnitt 14. Offen: Joruns Porträt, echte Texte, Regentropfen, die Haken aus Abschnitt 12. Baut auf `docs/brunnenplatz.md` (Platz = Herz der Stadt), `docs/town.md` (Siedler, Shops, Wege, Netz), `docs/stadtbau_konzept.md` (jedes Ereignis bekommt einen Moment) auf. Namen, Texte und Zahlen sind Platzhalter. Figur, Porträt und Dialogtexte entstehen bei den dafür vorgesehenen Agenten; hier stehen nur Rolle, Haken und Art-Vertrag. Die spätere, größere Bedeutung des Händlers (Abschnitt 12) wird **jetzt nicht** gebaut, bekommt aber ihre Haken.

---

## 0. In einem Absatz

Sobald der Brunnenplatz steht, kommt in unregelmäßigen Abständen eine kleine **Karawane** über einen alten Karrenweg aus dem Westen in die Stadt: ein Planwagen, ein zotteliges Zugtier, der Händler **Jorun** (Name aus `stadt_westen_konzept.md`, dort schon als Karawanenführer angelegt). Sie fährt bei Tag, hält am Rand des Brunnenplatzes, klappt den Wagen zu einem Marktstand auf und bleibt ein bis zwei Tage. Er verkauft Dinge, die es sonst nicht gibt (Fernes, Saatgut, ab und zu eine Kuriosität), und kauft, was die Stadt im Überfluss hat, einiges davon gerade besonders teuer. Nachts schließt der Stand, das Licht im Wagen glimmt. Dann rollt sie wieder fort. Alles ist **ein Ereignis**: Glocke in der Ferne, Einfahrt, Aufbau, Leben am Stand, Abbau, Abfahrt.

---

## 1. Ziele und Grenzen

**Ziele**
1. Der Platz bekommt einen Zweck über „Gründung" hinaus: Er ist der Ort, an dem die Welt in die Stadt kommt.
2. Unregelmäßig, aber planbar: Man soll sie verpassen *können*, aber nie unfair. Sie bleibt mindestens einen vollen Tag, die Karte zeigt sie, das STADT-Fenster nennt eine Spanne.
3. Ein Handel, der sich anders anfühlt als Gustav, Torben, Esma: **begrenzter, wechselnder Vorrat**, „Gesuchtes" mit Aufpreis, eine Kuriosität pro Besuch.
4. Sichtbar lebendig: Siedler gehen zum Stand, Krähen setzen sich auf die Plane, die Waren liegen sichtbar auf der Auslage und verschwinden, wenn sie verkauft sind.
5. Bewährte Architektur: **Kalender und Bewegung sind reine Funktionen** von Welt-Seed und Uhr (wie Siedler und Wetter), nur der Vorrat und die Standwahl sind Host-Zustand.

**Nicht jetzt** (Haken in Abschnitt 12): Handel zwischen Städten, Bestellungen auf den nächsten Besuch, Begleitaufträge, Mitreisende, die sich niederlassen, eigene Karawanserei, Story um Jorun, Questtafel-Aushänge von Jorun, Wachsen der Karawane über mehr als einen Wagen hinaus (nur vorbereitet).

---

## 2. Die Figuren und Dinge

### 2.1 Jorun, der Händler (Rolle für den Figuren-/Dialogagenten)
- **Wer:** reist seit Jahren zwischen den letzten bewohnten Orten; kennt Hallgrat im Westen, die Wegsteine, Gerüchte. Freundlich, schlitzohrig, erzählt gern, aber nie vom Weg selbst (warum er die Nacht überlebt, bleibt sein Geheimnis: Haken für später).
- **Aussehen (Vorschlag):** älter, kräftig, mehrere Lagen Mantel übereinander in verwaschenen Erdtönen mit einem Streifen **Karawanenblau**, breitkrempiger Hut mit Schnüren voller kleiner Anhänger (Glasperlen, Federn, ein Schlüssel), Taschen überall, Laternenstab, den er beim Gehen als Stock benutzt. Liest sich als Silhouette sofort als „Händler", nicht als Siedler.
- **Bis zum ersten Gespräch** heißt er „FREMDER HÄNDLER" (Silhouetten-Porträt, `known_flag` `knows_jorun`, wie beim Ritter).

### 2.2 Der Wagen
Ein **Planwagen**, der sich zu einem Stand aufklappt. Gleicher Renderer wie Gustavs Wagen (`tools/art_wagon.py`, Ellipsoide), aber heil, beladen und bunter:
- vier Speichenräder (drehen sich beim Fahren), Plane in Karawanenblau mit aufgenähten Flicken, Kisten und Fässer hinten festgezurrt, Töpfe und Laternen an Haken, eine **Wagenglocke** am Kutschbock.
- **Aufgeklappt:** die rechte Seitenwand klappt zur **Theke** herunter, die Plane wird an zwei Stangen zu einem **Vordach** ausgespannt, ein Holzschild wird eingehängt, kleine Wimpel. Auf Theke und Stufen liegen die **echten Waren** (Item-Icons des aktuellen Vorrats, Abschnitt 6.5).
- **Nachts:** Seitenwand hochgeklappt, Plane zu, ein warmes Licht schimmert durch die Plane, Laterne am Haken.

### 2.3 Das Zugtier
**Empfehlung: ein Zottelochse** („Moosbüffel"): breit, langes zotteliges Fell mit Moos, gebogene Hörner, ein Joch mit Glöckchen und einer kleinen Laterne. Bodenständig, in der 3/4-Sicht klar lesbar, passt zu Gustavs Wagen und zur Wiese. Er wird nie verletzt, kann nicht angegriffen werden, ist kein Wildtier (keine Beute, kein Kampf; Regel „kein Tier wird verletzt").
Alternativen zur Entscheidung: ein großer, blasser **Lastkäfer** (fremder, magischer) oder **kein Tier** (Jorun zieht einen Handkarren: billiger, aber keine „Karawane").

### 2.4 Größe der Karawane
Stufe 1 = **ein Wagen, ein Tier, Jorun**. Die Daten erlauben `wagons` pro Stadtstufe (Haken): ab DORF ein zweiter, kleinerer Vorratskarren mit einer Begleiterin (Joruns Tochter, Hallgrat-Konzept „Jorun und Familie"), ab STADT ein dritter. Nicht in Stufe 1.

---

## 3. Der Besuchskalender (wann sie kommt)

### 3.1 Erste Ankunft
- Bedingung: Brunnenplatz **fertig** (`has_heart()`), Eröffnung vorbei (`opening_over`).
- `first_day` = der Morgen nach der Fertigstellung des Platzes (`first_delay` 1; also nicht am selben Morgen, sondern „es hat sich herumgesprochen"). `first_day` ist der einzige Wert, den der Host dafür speichern muss.
- Die erste Ankunft spielt immer die ganze Einfahrt mit Banner „EINE KARAWANE KOMMT ZUM ERSTEN MAL" (wenn jemand in der Stadt ist; sonst steht sie einfach da, siehe 3.4).

### 3.2 Unregelmäßigkeit als reine Funktion
`CaravanRules.visits(seed, first_day, until_day)` liefert die Besuche `[{i, arrive_day, leave_day}]`, gerechnet aus dem Welt-Seed:
- Abstand zwischen Abfahrt und nächster Ankunft: **2 bis 5 Tage**, gewichtet (3 am häufigsten).
- Aufenthalt: **1 Tag** (Ankunft morgens, Abfahrt am Nachmittag des Folgetags) oder **2 Tage** (selten, 25 %).
- **Wetter:** Liegt `WeatherRules` (auch rein) zur Ankunftszeit auf `storm`, verschiebt sich die Ankunft um einen Tag. Ein Sturm während des Aufenthalts lässt sie nicht abreisen, sondern den Stand schließen (5.5).
- **Sondernächte:** Ist für die Nacht vor der Ankunft eine Flut-/Neumondnacht angesagt (`night.json`), kommt sie trotzdem am Morgen (sie reist ja nur bei Tag), aber Jorun hat Gesprächszeilen dazu.
Weil alles rein ist, rechnet jeder Peer dasselbe, nichts muss synchronisiert werden außer `first_day`. Tagesschritte per Cheat (F4, Tag/Nacht) sind unkritisch: Der Kalender folgt `TimeManager.day`.

### 3.3 Tagesuhr eines Besuchs (Anteil des Tages, 12-Minuten-Tag)
| Zeit | Phase |
|---|---|
| 0,17 (Nachtende) | bricht am Rand des geladenen Wegs auf (unsichtbar, nur Karte) |
| 0,17 – ~0,30 | **Anreise** auf dem Karrenweg (Länge / Tempo, 4.2) |
| ~0,30 | Einfahrt in die Stadt, **Halt** am Stellplatz |
| + 10 s | **Aufbau** (Abschnitt 5.2) |
| bis 0,78 | **Stand offen** |
| 0,78 – 0,17 | **Nacht**: Stand zu, Licht im Wagen, Jorun schläft im Wagen (unsichtbar) |
| Abfahrtstag 0,62 | **Abbau**, dann Abfahrt; um ~0,75 hat sie den sichtbaren Bereich verlassen |
Die Abfahrt fällt nie in die Nacht. Steht jemand gerade im Handelsfenster, wartet der Host höchstens 0,03 Tage (ca. 20 s) mit dem Abbau.

### 3.4 Wenn niemand da ist
Die Karawane existiert unabhängig davon, ob ein Spieler in der Nähe ist: Ihre Position ist immer `f(Uhr)`. Wer mitten im Aufenthalt in die Stadt kommt, sieht den offenen Stand (kein Aufbau, aber das Betreten-Banner hat eine Zeile „DIE KARAWANE IST DA · BIS MORGEN"). Wer auf dem Karrenweg unterwegs ist, kann ihr **begegnen** (sie fährt an einem vorbei, man kann sie nicht ansprechen, solange sie fährt: Jorun ruft nur einen Gruß).

### 3.5 Was der Spieler weiß
- **STADT-Tab:** „KARAWANE: IN DER STADT · NOCH 1 TAG" / „ZULETZT VOR 2 TAGEN · ERWARTET IN 1–4 TAGEN" (die Spanne aus den Regeln, nie der genaue Tag: unregelmäßig, aber planbar).
- **Karte:** Wagenmarke am Stellplatz (mit „NOCH … "), am Anreisemorgen als wandernde Marke auf dem Weg.
- **Vorabend:** Siedler haben am Abend vor der Ankunft eigene Chat-Zeilen („Morgen kommt Jorun, ich spür's im Knie."): ein Pool `caravan_eve` in `chat`, rein aus dem Kalender abgeleitet.
- **Glocke:** Ab ca. 25 s vor der Einfahrt hört man die Wagenglocke und das Rädergeknarre positional aus der Wegrichtung.

---

## 4. Der Weg (woher sie kommt)

### 4.1 Der Karrenweg
Ein neuer gebackener Weg in `data/ground.json` `paths`, id `caravan_road`, **neuer Stil `ruts`**: zwei parallele, festgefahrene Radrinnen (je ~6 px) mit einem Grasstreifen in der Mitte, Rand wie der Fußweg, gelegentlich ein Schlagloch mit Pfütze (bei Nässe `g_puddle`). Damit sieht man ihm an, dass hier Räder fahren, nicht Füße. Erweiterung von `tools/bake_ground.py` (ein Stil-Schlüssel, kein neues Werkzeug).
- **Gebaut statt dieses Vorschlags (Schritt 2):** Die Hütte liegt in einer flachen Senke, deren einziger ebener Ausgang nach **Norden** führt; nach Westen gibt es keinen Weg auf Ebene 0 (die flache Route wäre 910 Tiles lang). Der Karrenweg führt deshalb von der Ostseite der Hütte (Tile 798, 668) östlich an Torbens Lager vorbei und am Holzfällerhaus entlang nach Norden bis Tile (766, 428), ≈ 4000 px, und läuft dort in die Wiese aus. Siehe Abschnitt 14.
- **Ursprünglicher Vorschlag:** vom Ende des `footpath_branch` östlich der Wegkreuzung (~ Tile 533, 697), wo der Wegweiser schon in die Welt zeigt, auf Ebene 0 nach Osten bis an den Rand des Hüttenhofs (~ Tile 770, 680). ~240 Tiles. Er knüpft an die alte Welt an und gibt dem Spieler nebenbei eine Straße. Route muss auf flachem Ebene-0-Boden liegen (`relief.png` prüfen); der Baker hält wie bei jedem Pfad Props frei.
- **Westliches Ende:** Dort, wo der Weg ausläuft, „beginnt die Ferne". Die Karawane erscheint und verschwindet dort, das Ende liegt weit außerhalb jeder Sicht von der Stadt.

### 4.2 Die Fahrt
- Tempo 34 px/s (Ochse im Schritt, langsamer als Ellies Gehen); 240 Tiles ≈ 113 s ≈ 0,16 Tag. Passt in 0,17 – 0,33.
- Position = Punkt auf der gebackenen Polylinie bei `(t − abfahrt) · tempo` (`Settler._along`-Logik). Ausrichtung aus der Tangente, 8 Richtungen.
- **Letztes Stück** vom Wegende am Hof zum Stellplatz: `TownManager.walk_route` (`TownWays`, kennt Bauten, Stämme, Wege), einmal pro Besuch gerechnet und gecacht. Findet sich kein Weg, hält die Karawane am Wegende (siehe 5.1 Notlösung).
- Die Karawane ist **während der Fahrt nicht fest** (kein Kollisionskörper), damit sie nie Spieler einklemmt; Gegner nehmen sie nicht wahr (keine Gruppe `players`, nicht `predators`). Sie fährt nur bei Tag, also nie durch eine Nacht.
- Geladen wird sie nur gezeichnet, wenn ein Spieler nahe ist (wie Stadtbauten: 700 px Sicht), aber der Knoten existiert immer.

---

## 5. Ankunft, Stand, Abfahrt (Ablauf und Animationen)

### 5.1 Der Stellplatz
Der Brunnenplatz ist ein Teil mit fester Fußfläche, kein anderes Teil darf ihn überlappen: **sein Rand ist garantiert frei**, nur der Brunnen in der Mitte ist fest. Darum steht die Karawane dort.
- `data/caravan.json` `slots`: vier Kandidaten relativ zur Platzmitte (W, O, SW, SO), je `{at, face, foot [w, d], front [w, d]}`: Wagenfußfläche ~76 × 26 px, davor ein Kundenstreifen 60 × 24 px, das Tier steht vor dem Wagen.
- Der Host wählt zur Ankunft den ersten Kandidaten, dessen Fuß + Front frei von Bauten (Datenvergleich wie `check_place`), Brunnen und Spielern ist und den die Route erreicht; bevorzugt die Seite zum Karrenweg. Ergebnis wird mit dem Besuch gespeichert und gesendet (nicht neu gerechnet, falls sich währenddessen etwas ändert).
- **Notlösung:** Ist keiner frei (ungewöhnlich, Platz rundherum zugebaut), hält die Karawane am Hof-Ende des Karrenwegs mit dem Bark „Euer Platz ist voll. Ich steh hier draußen."
- **Während sie steht:** Baumodus verweigert Fundamente in ihrer Fläche („DIE KARAWANE STEHT HIER"), `walk_route` behandelt Wagen und Tier als Hindernis (Cache beim Ankommen/Abfahren verwerfen), der Wagen bekommt einen festen Körper erst, wenn seine Fläche frei ist (lokale Prüfung, nie in einen Spieler hinein).

### 5.2 Einfahrt und Aufbau (~14 s, alles aus der Uhr, jeder Peer gleich)
1. **Glocke und Geknarre** aus der Ferne (positional), Staub hinter den Rädern (`step` puff), Räder drehen sich, der Wagen wippt über Unebenheiten (ganze Pixel), Laterne und Töpfe schwingen (`sway_rows`), der Ochse geht im Schritt, Jorun sitzt auf dem Kutschbock mit den Zügeln (`drive`).
2. **Halt:** Ochse bleibt stehen, schnaubt (Kopfwurf), Wagen ruckt nach, Glocke klingt aus. Kamerastoß 0.
3. Jorun **klettert ab** (`climb_down`), legt einen Keil unter ein Rad (`chock`, Holzklack).
4. **Aufklappen:** Seitenwand fällt zur Theke (Wagen-Sheet `setup` 8 Frames, Holzschlag), Plane wird zum Vordach ausgespannt (Stoffrauschen), Schild wird eingehängt (Kette), Jorun stellt zwei Kisten ab (`carry_crate`), Wimpel flattern. Die Waren „fallen" als Icons auf die Auslage (Item für Item, Abschnitt 6.5).
5. Jorun tritt hinter die Theke, **ruft aus** (`call`), TownBanner „DIE KARAWANE IST DA · JORUN" mit Glocke (nur wer in der Stadt/Nähe ist; beim ersten Besuch die große Fassung).
6. `TownManager.event("caravan_arrived")` → `SettlerChatter` reagiert (Gustav: Freudenzeile, Valdric: misstrauisch).

### 5.3 Leben am Stand (offen)
- **Jorun-Zyklus** (Spot-`clips` + `pause` wie Valdrics Übung): `counter` (lehnt an der Theke, trommelt), `arrange` (rückt Waren), `count` (zählt Münzen), `smoke` (Pfeife, ein Rauchfaden), `call` (ruft aus, nur wenn jemand 80–160 px entfernt ist), dazu Barks.
- **Kommt ein Spieler** nahe: Jorun dreht sich zu ihm (`face` zur Spielerin), `wave` beim ersten Kommen des Tages.
- **Ochse:** `graze` (Kopf unten, Gras rupft er nicht weg: reine Animation), `idle`, `swish` (Schwanz), `shake` (schüttelt sich, Glöckchen), nach Mittag `lie_down`/`lie`.
- **Siedler besuchen den Stand:** ein neuer Spot `caravan` (Anker `of: "caravan"` = Kundenstreifen; ohne Karawane gilt `fallback`), den Gustav, Torben, Maren in ihrer Pause statt `fire` nutzen, wenn die Karawane da ist (`schedule_caravan` ersetzt einzelne Fenster, oder `resolve_spot` lässt `fire` → `caravan` gelten). Clip `haggle`/`idle`, Chatter-Zeilen zwischen Siedler und Jorun (`SettlerChatter`, data/chatter.json).
- **Krähen:** Wagen und Vordach tragen `perches` (`RoofPerch`), `TownCritters` setzt sie gern auf die Plane.
- **Ausverkauft:** leere Stellen auf der Auslage; ist alles weg, Bark „Ihr habt mich leergekauft!" und Jorun sitzt auf der Deichsel (`sit`).

### 5.4 Nacht
- 0,78: Jorun klappt die Theke hoch (Aufbau rückwärts, nur das Brett), zündet die Laterne (`NightLight`, warm, klein, **kein Stadtlicht-Kreis**: er zählt nicht für Bauen oder Spawnschutz), steigt in den Wagen (unsichtbar). Licht schimmert durch die Plane (Glow-Sheet). Ochse liegt.
- E am Wagen nachts: Prompt „KLOPFEN" → gedämpfte Zeile aus dem Wagen („Morgen früh, Kind. Ich schlafe.").
- **Angriff/Alarm** (`TownManager.fear_on`, `alert_on`): Laterne wird gedimmt, Ochse steht auf und muht unruhig; nichts weiter. Wagen, Tier und Jorun sind unverwundbar und für Schattenwesen kein Ziel (wie Siedler; Gebäudeschaden gibt es nicht).

### 5.5 Wetter
- **Regen:** Jorun bleibt unter dem Vordach, Tropfen laufen von der Plane (`drips` am Vordachrand, nur bei `rain_now()`), Ochse dampft leicht.
- **Sturm:** Stand schließt (Theke hoch, Vordach eingerollt), Wimpel peitschen, Jorun im Wagen; nach dem Sturm wieder Aufbau (verkürzt). Kein Handel währenddessen („GESCHLOSSEN · STURM").

### 5.6 Abbau und Abfahrt
Ab 0,62 am letzten Tag: Bark „Ich muss weiter, solange es hell ist.", Abbau (Aufbau rückwärts: Waren in Kisten, Vordach, Theke, Keil), Jorun winkt (`wave`), steigt auf, Glocke, Fahrt zurück über den Karrenweg. Abschiedszeile im Banner: „DIE KARAWANE ZIEHT WEITER". Alle Restwaren des Besuchs verfallen (neuer Besuch = neuer Vorrat).

---

## 6. Der Handel

### 6.1 Ansprechen und Handeln
Wie bei Esma: E am Jorun = **ANSPRECHEN** (einmal am Tag: eine `chat`-Zeile, +10 Vertrauen; beim allerersten Mal der Dialog `caravan_first` mit Porträt, setzt `knows_jorun`), danach **HANDELN** öffnet `ShopWindow` `caravan` (`BoardWindow` rahmt Jorun links, das Brett hängt rechts). Nur während der Stand offen ist; während Fahrt/Aufbau/Nacht zeigt der Prompt nichts bzw. „KLOPFEN".

### 6.2 Reiter
| Reiter | Inhalt |
|---|---|
| **WAREN** (kaufen) | der Vorrat dieses Besuchs: Zeilen mit Restmenge („NOCH 3"), oben die **Kuriosität** mit goldenem Rand |
| **ANKAUF** (verkaufen) | was er nimmt; oben 2–3 **GESUCHT**-Zeilen mit Aufpreis und begrenzter Menge („NIMMT NOCH 10"), darunter Normalankauf |

### 6.3 Was er verkauft (Pools in `data/caravan.json`, pro Besuch gezogen)
Jeder Besuch zieht aus Pools nach `CaravanRules.offer(seed, i, stadtstufe, vertrauen)`; rein, also für alle gleich:
- **Fernes (3–4 Zeilen):** Waren aus Gegenden, die Ellie (noch) nicht kennt: Wüstenfrüchte und -material (`sun_date`, `quartz_aloe`, `sun_fig`, …), Kräuter, Mineralien. Bewusst nichts von Tieren (Regel „kein Tier wird verletzt").
- **Saatgut (1–2 Zeilen):** genau der Haken aus `docs/farming.md` („Samen, die nur auf Feldern wachsen, Quellen: Truhen, Händler"): Feldsamen mit `origin: "field"`. Braucht neue Crops (eigene Absprache, siehe 13); bis dahin Wildsamen der vorhandenen Crops.
- **Grundbedarf (2–3 Zeilen):** Seil, Bretter, leere Phiolen, Heiltränke Stufe 1–2: etwas teurer als in der Stadt, dafür ohne Vertrauen.
- **Kuriosität (genau 1):** selten und teuer, einmal pro Besuch für alle: ein Edelstein oder Kristall niedriger Stufe, später ein **Talisman** (der Talisman-Plan nennt „Händler" als fehlende Quelle), ein seltener Köder, ein Bauplan (Haken). Vertrauensstufen öffnen bessere Kuriositäten-Pools.
- Menge pro Zeile begrenzt (`stock` je Eintrag), **gemeinsamer Vorrat** für alle Spieler (eine Stadt, ein Zustand; wer zuerst kauft, kauft).

### 6.4 Preise und Ankauf
- **Tageskurs:** jede Ware bekommt pro Besuch einen Faktor 0,85–1,15 (rein aus Seed + Besuch). Vertrauen gibt bis zu −10 %.
- **Ankauf:** breite Liste (Holz, Stein, Bretter, Pflanzen, Pilze, Erz, Leere-Splitter …) zu ~50 % der Verkaufswerte anderer Händler; **GESUCHT:** 2–3 Waren pro Besuch zu 150–220 % bis zu einer Menge (gemeinsam gezählt). So lohnt sich Sammeln zwischen den Besuchen, und man hat einen Grund, zu kommen.
- Preise in Kupfer wie überall (`Currency`). Abstimmung später gegen die übrigen Läden (kleine Tabelle wie `sim_refine.py` ist nicht nötig, eine Liste in der Doku reicht).

### 6.5 Waren sichtbar machen
Die Auslage hat feste Ablageplätze (`display` in `caravan_art.json`: 8 Punkte auf Theke und Stufen). Jede Warenzeile belegt einen Platz mit ihrem **16×16-Icon** (welt-beleuchtet, die Kuriosität mit leisem ungelittenem Schimmer). Ist eine Zeile ausverkauft, verschwindet ihr Icon mit einem kleinen Hüpfer. Man sieht von weitem, was es heute gibt.

---

## 7. Technik

### 7.1 Teile
| Was | Wo | Aufgabe |
|---|---|---|
| `CaravanRules` | `src/town/caravan_rules.gd` (rein, statisch) | Kalender `visits`, `visit_at(day)`, Phase `phase(visit, time)` → {state, k}, Angebot `offer`, Preise, Stellplatz-Prüfung auf Daten |
| `CaravanManager` | Kind `Caravan` von `TownManager` (`town.caravan`), Host entscheidet | Zustand pro Besuch (Stellplatz, Restvorrat, Gesucht-Zähler), Handel, RPCs, Snapshot, Speichern; `register_outpost("caravan", front)` / entfernen; Baublock; Event an Chatter |
| `CaravanView` | `src/town/caravan_view.gd`, Node2D, y-sort, unter dem Stadtknoten | Wagen (Sprite + Teile + Glow + Auslage), Ochse, Laterne, Staub, Glocke, Töne; liest nur Uhr + Besuch |
| `CaravanMerchant` | `src/town/caravan_merchant.gd`, `extends Settler` | Jorun: übernimmt Clips, Sprite, ANSPRECHEN/HANDELN, Vertrauen, Chat, Kartenmarke; überschreibt die Positionslogik (auf dem Kutschbock bei Fahrt, Spots relativ zum Stellplatz, unsichtbar nachts / ohne Besuch) |
| Daten | `data/caravan.json`, `data/settlers.json` `jorun` (`away` true, `counts` false, `visitor` "caravan", Spots, Chat), `data/shops.json` `caravan` (`dynamic: "caravan"`), `data/dialogue.json`, `data/chatter.json` | |

### 7.2 Netz und Zustand
- **Rein (jeder Peer):** Kalender, Phase, Position auf dem Weg, Animationen, Angebot (Zeilen, Preise, Kuriosität). Wie Siedler: nichts zu synchronisieren, kein Auseinanderlaufen.
- **Host (gespeichert im Stadtzustand `town.caravan`):** `first` (Tag), `visit` {i, slot, left {item: n}, wanted {item: n}}, Vertrauen/`talked` über den normalen Bewohner-Weg (`residents`-ähnlicher Eintrag für `away`-Personen, wie Esma).
- RPCs: `_rpc_caravan_visit` (Stellplatz + Restvorrat bei Ankunft), `_rpc_caravan_stock` (nach jedem Kauf/Verkauf), Teil des `_rpc_snapshot` für Beitretende. Handel über einen eigenen `request_caravan_trade(mode, item, n)` (prüft: Besuch offen, Nähe zum `caravan`-Outpost, Restmenge, Geld, Platz, Vertrauen) – der allgemeine `_host_trade` bleibt unberührt.
- Dev-Overrides (ENTWICKLER → KARAWANE: JETZT HOLEN / ABREISEN LASSEN / NÄCHSTER BESUCH): Host setzt einen erzwungenen Besuch `force {arrive_time, leave_day}`, der wie die Wetter-Override per RPC an alle geht.

### 7.3 Änderungen an Bestehendem (klein halten)
- `ShopWindow`: Kind `buy`/`sell` liest bei `dynamic` die Zeilen von `town.caravan.rows(mode)` statt aus `shops.json`; zeigt Restmenge (`tag` „NOCH 3"), „GESUCHT" mit Aufpreis-Farbe, Kuriosität mit Goldrand. `_press` ruft `request_caravan_trade`.
- `TownManager.check_place`: neuer Grund „DIE KARAWANE STEHT HIER" (Rechteck aus dem Besuch). `walk_route`: Hindernisrechteck der Karawane, Cache-Verwerfen bei Ankunft/Abfahrt.
- `Settler.resolve_spot`: Anker `of: "caravan"` gilt nur, solange die Karawane offen ist, sonst `fallback`.
- `PauseMenu` STADT-Tab: eine Zeile KARAWANE; Jorun **nicht** in der Bewohnerliste (wie Esma). `MapWindow`: Marke `caravan` in `data/map_markers.json`.
- `TownBanner`: Zeile beim Betreten, Ankunft/Abfahrt.
- `bake_ground.py`: Wegstil `ruts`.

### 7.4 Leistung
Ein Knoten, wenige Sprites, Route einmal pro Besuch. Auslage-Icons nur bei Vorratsänderung neu. Kein Physikkörper unterwegs.

---

## 8. Art-Vertrag

> Laut CLAUDE.md macht ein eigener Agent Figuren/Porträts (Jorun) und neue Art soll an den `gpt-6.1-terra`-Subagenten gehen (falls verfügbar; sonst wie bisher der Hauptagent). Gameplay, Einbindung und Prüfung bleiben beim Hauptagenten. Bis die Bilder da sind: `Settler`-Platzhalterfigur, Wagen als schlichtes Rechteck mit Plane.

### 8.1 Jorun (`assets/characters/jorun.png`, `jorun_glow.png`, `data/jorun_rig.json`, Settler-Rig-Format)
8 Richtungen (E SE S SW W NW N NE), Frame-Größe wie Gustav/Torben (~88×104), Füße mittig unten. Clips:
| Clip | Frames | Notiz |
|---|---|---|
| `idle` | 4 | Atmen, Hutanhänger schwingen |
| `walk` | 8 | mit Laternenstab als Stock |
| `drive` | 4 (Schleife) | sitzend, Zügel, Wippen; Füße = Kutschbock-Anker |
| `climb_down` / (rückwärts = Aufsteigen) | 8 | vom Bock auf den Boden |
| `chock` | 6 | bückt sich, Keil unters Rad |
| `carry_crate` | 6 | Kiste tragen + abstellen |
| `counter` | 6 | lehnt an der Theke, trommelt |
| `arrange` | 6 | rückt Waren |
| `count` | 6 | Münzen zählen |
| `smoke` | 6 | Pfeife, Rauch als eigenes Partikel |
| `call` | 6 | Hand am Mund, ausrufen |
| `wave` | 6 | Gruß/Abschied |
| `present` | 6 | hält einer Kundin etwas hin (im Handelsfenster) |
| `sit` | 4 | auf der Deichsel |
`jorun_glow`: nur Laternenstab-Licht. Porträt `assets/ui/portrait_jorun.png` (103×153, `docs/dialogue_art.md`), sprechend wie Gustav (`SpeechPortrait`) – späterer Schritt.

### 8.2 Wagen (`tools/art_caravan.py` → `assets/town/caravan/`)
Ellipsoid-Renderer wie `art_wagon.py`, Palette: Holz der erneuerten Hütte (plum-violett), Plane Karawanenblau `#3d5a8a`-Familie (gegen Teal/Violett der Welt abgesetzt), Messingglocke.
- `wagon_roll.png`: 8 Richtungen × 4 Frames (Raddrehung, Wippen über die Frames).
- `wagon_stand.png`: eine Ausrichtung **pro Stellplatz-Seite** (Seite W/O: Profil, SW/SO: Dreiviertel; vier Bilder), je Spalten: 0 zu, 1–8 Aufklappen, 9 offen, 10–12 Nacht (Theke hoch, Plane zu).
- Teile mit eigenem Wind (`sway`): Vordach-Saum, Wimpel, Schild, Laterne, Töpfe.
- `_glow`: Laterne, Licht durch die Plane (nachts), Glocke-Glanz nein.
- `caravan_art.json`: Füße, Kutschbock-Anker je Richtung/Frame, `display`-Punkte, `perches`, Kollisionsrechteck, Laternenpunkt, Tier-Anker.

### 8.3 Ochse (`tools/art_caravan.py ox` → `assets/town/caravan/ox.png`)
Woodland-Format (wie `art_woodland.py`: 8 Richtungen, Füße unten mittig, ~80×64): `idle` 4, `walk` 8 (Schritt passend zu 34 px/s), `graze` 6, `swish` 4, `shake` 6, `snort` 4, `lie_down` 6 (rückwärts = aufstehen), `lie` 4. Joch, Glöckchen, Laterne am Joch (eigene Glow-Zeile). Nie emissiv sonst.

### 8.4 Weg
`caravan_road` Stil `ruts` im Baker (Radrinnen, Grasmitte, Schlaglöcher, Pfützen). Kein neues Bild-Werkzeug.

---

## 9. Ton (`py -3 tools/audio_caravan.py` → `assets/audio/caravan/`, synthetische Platzhalter)
`bell` (Wagenglocke, weit hörbar, 3 Varianten), `wheels_loop` (Knarren + Rollen), `ox_snort`, `ox_low`, `ox_bells` (Jochglöckchen beim Gehen), `flap` (Theke fällt), `cloth` (Plane), `chain` (Schild), `crate` (Kiste), `chock`, `coins` (Kauf), `coins_sell`, `knock` (Klopfen nachts), `door_muffled`. Positional, SFX-Lautstärke, Glocke mit Hall aus Wegrichtung.

---

## 10. Texte (Platzhalter, für den Dialog-Writer)
Dialoge: `caravan_first` (erste Begegnung), Chat-Pools in `settlers.json jorun.chat`: `spot` (counter, arrange, sit …), `weather` (Regen, Sturm), `night` (durch die Plane), `eve` (Vorabend, bei den Siedlern), `sold_out`, `leaving`, `arrive`, `greet_road` (wenn man ihm unterwegs begegnet), Ladenzeilen in `shops.json caravan.lines` (`open`, `buy`, `sell`, `poor`, `full`, `wanted`). Chatter-Szenen Gustav↔Jorun, Valdric↔Jorun.

---

## 11. Bauschritte (Vorschlag)

1. **Regeln + Daten + Manager, ohne Art:** `caravan.json`, `CaravanRules` (Kalender, Phase, Angebot, Preise), `CaravanManager` (Besuch, Stellplatz, Vorrat, Handel, Speichern, Snapshot), Jorun als `CaravanMerchant` mit Platzhalter, Shop `caravan` dynamisch, Dev-Knöpfe. Test `tools/test_caravan.tscn` (Kalender deterministisch/Spannen, Sturm-Verschiebung, Phasen, Angebot gleich auf allen Seeds, Stellplatzwahl inkl. zugebaut, Kauf/Verkauf/Restmenge/Gesucht, Speichern/Laden, Baublock).
2. **Weg + Fahrt:** `caravan_road` (Stil `ruts`, Bake), Fahrt entlang der Polylinie, Hof-Route, Halt, Hindernis in `walk_route`, Kartenmarke, STADT-Zeile.
3. **Art:** Wagen + Ochse (`art_caravan.py`), Jorun (Figuren-Agent), Auslage-Icons, Glow, Wind-Teile, Aufbau/Abbau aus der Uhr. Vorschau `tools/preview_caravan.tscn -- --capture=/abs.png [--phase=arrive|setup|open|night|leave] [--night]`.
4. **Leben:** Siedler-Spot `caravan` + Chatter, Krähen auf der Plane, Regen/Sturm/Nacht/Alarm, Banner, Töne.
5. **Netz:** `tools/test_caravan_network.tscn` (zwei Prozesse, freier Loopback-Port): später Beitritt mitten im Aufenthalt, Kauf durch Client, gemeinsamer Vorrat, Abfahrt.

---

## 12. Haken für später (nicht bauen, nur nicht verbauen)
- **Bestellungen:** „Bring mir beim nächsten Mal …" (Warteliste wie `orders`, Lieferung am nächsten Besuch).
- **Mitreisende:** neue Siedler kommen mit der Karawane an (Ankunftsart `arrive.caravan`), statt aus dem Nichts.
- **Handel zwischen Städten:** Jorun als Verbindung nach Hallgrat; Waren aus der Stadt mitgeben, Gewinn beim nächsten Besuch.
- **Die Stallungen von Hallgrat** (Beschluss 2026-11-13): Um **Stufe 15** erzählt Jorun Ellie zum ersten Mal von dem großen Stall am Karrenhof von Hallgrat, dem späteren Ort der Reittiere (docs/stadt_westen_konzept.md 8.19a). Sein Westweg zweigt nördlich von Glimmrast von seinem Karrenweg ab.
- **Karawanserei/Marktplatz** als Teil: mehr Wagen, häufigere Besuche, eigener Stellplatz.
- **Begleitaufträge** (Karawane in Not am Weg, Hallgrat-Konzept 8.x), Questtafel-Aushänge von Jorun (`has_met`).
- **Story:** warum er nachts überlebt; Briefe, Nachrichten, Gerüchte über Orte (Karte deckt Hinweise auf).
- **Wachsende Karawane** über `wagons` je Stadtstufe.

---

## 13. Offene Entscheidungen
1. **Zugtier:** Zottelochse (Empfehlung) / Lastkäfer / Handkarren ohne Tier?
2. **Herkunft:** gebackener Karrenweg von Westen an die Wegkreuzung angeschlossen (Empfehlung) oder nur „erscheint außerhalb der Sicht" ohne Straße (billiger, aber man kann ihr nie begegnen)?
3. **Rhythmus:** 2–5 Tage Pause, 1–2 Tage Aufenthalt bei 12-Minuten-Tagen (≈ 25–60 min Spielzeit zwischen Besuchen) – passt das?
4. **Vorrat:** gemeinsam für alle Spieler (Empfehlung, „eine Stadt") oder pro Spieler?
5. **Name:** Jorun (aus dem Hallgrat-Konzept) übernehmen?
6. **Feldsamen:** Sollen mit der Karawane die ersten nur-auf-dem-Feld-Samen kommen (braucht neue Crops und Art) oder erst später?

---

## 14. Stand der Umsetzung

**Schritt 1 (2026-11-13): Regeln, Daten, Manager, Handel, Platzhalter.**
- `data/caravan.json`: Kalender (`first_delay`, `gap`, `stay`, `storm`, Zeiten), Fahrt/Aufbau/Abbau in Sekunden, vier Stellplätze am Platzrand (`slots`: `at` relativ zu den Füßen des Platzes, `foot`, `front`, `side`), Warengruppen `curio`/`far`/`seed`/`basic` (`count`, Einträge mit `price`, `stock`, `weight`, optional `level` = Stadtstufe, `trust`), Ankauf `buys`, `wanted`, `jitter`, `trust_discount`.
- `CaravanRules` (src/town/caravan_rules.gd, rein): `visits` (gecacht, Sturm verschiebt die Ankunft, `set_storm_override` für Tests), `visit_at`, `next_visit`, `window`, `phase` (away/coming/setup/open/night/storm/teardown/going), `offer` (pro Besuch aus Seed + Index + Stadtstufe), `buy_price` (Vertrauen bis −10 %), `sell_price` (Gesucht-Preis bis zum Limit, dann normal), `slot_rect`/`front_rect`/`pick_slot`.
- `CaravanManager` (src/town/caravan_manager.gd, Kind `Caravan` von `TownManager`, `town.caravan`): Host setzt `first_day` sobald der Platz steht und die Eröffnung vorbei ist, legt pro Besuch den Datensatz `{i, a, l, slot, lv, sold, took}` an (Stellplatz und Stadtstufe werden bei Ankunft festgehalten), `request_trade` → `_host_trade` (Nähe zu Jorun ≤ `reach` des Shops, offen, Vorrat, Geld, Platz, Vertrauen), `_rpc_counts`; gespeichert im Stadtzustand unter `caravan` (auch im Snapshot für Beitretende). Outpost `caravan` nur während der Stand steht (`TownManager.clear_outpost`). Banner „DIE KARAWANE IST DA" beim Öffnen in der Nähe, Stadt-Events `caravan_arrived` / `caravan_leaving` (lokal auf jedem Peer).
- `CaravanView` (Platzhalter-Wagen mit Ochse, gezeichnet): Fahrt, aufklappende Theke mit Vordach, Waren-Icons auf der Auslage (Ausverkauftes fehlt), Laterne; fest nur, wenn er steht und niemand in seiner Fläche ist.
- `CaravanMerchant` (Jorun): **Abweichung vom Konzept:** `extends Interactable` nach dem Muster von `InteriorResident`, nicht `Settler` (Settler hängt an Häusern, Stadtplätzen und Tagesplänen). E: ANSPRECHEN (erstes Gespräch nennt seinen Namen, Flag `knows_jorun`) → HANDELN, nachts/im Sturm KLOPFEN (Zeile durch die Plane). Platzhalterfigur bis `assets/characters/jorun.png` + `data/jorun_rig.json` existieren.
- `data/settlers.json` `jorun` (`away`, `visitor` "caravan", `enabled` false, `counts` false; Chat-Pools `first`, `any`, `wanted`, `evening`, `knock`, `knock_storm`), `data/shops.json` `caravan` (`dynamic: "caravan"`, Reiter WAREN / ANKAUF). `ShopWindow` liest bei `dynamic` die Zeilen von `CaravanManager.rows` (Restmenge, KURIOSITÄT mit Goldring, GESUCHT oben) und schließt sich, wenn der Stand zumacht.
- Stadt: `check_site` meldet „DIE KARAWANE STEHT HIER", `walk_route` geht um den stehenden Wagen, `met_residents` lässt Besucher (`visitor`) aus (keine Aushänge), STADT-Tab-Zeile KARAWANE (da / noch N Tage / „ERWARTET IN X BIS Y TAGEN").
- Entwickler: ENTWICKLER → KARAWANE: JETZT HOLEN / 2 TAGE / ABREISEN (`debug_come`, `debug_leave`; ein Dev-Besuch überdeckt einen Kalenderbesuch, der sich mit ihm überschneidet: `skip_until`).
- Fahrt in Schritt 1: von einem Punkt `come_from` px westlich des Herzens über `walk_route` zum Stellplatz (der gebackene Karrenweg kommt mit Schritt 2).
- Test: `Godot --headless --path . --fixed-fps 60 tools/test_caravan.tscn` (94 Prüfungen, `CARAVAN OK`).

**Schritt 2 (2026-11-13): Karrenweg und Fahrt.**
- `data/ground.json` Pfad `caravan_road` (`ruts: true`, Breite 30, `taper_out` 160). Route per Wegsuche über `relief.png`/`map_water.png`/`land_sdf.png` (nur Ebene-0-Boden, kein Wasser, ≥ 2,5 Tiles Abstand zu Wänden, Sperrkreise um Torbens Lager (791, 639) und das Holzfällerhaus (755, 482)).
- `tools/bake_ground.py`: Wegstil `ruts` (Spec-Schlüssel): Radrinnen durchgehend, keine Pflastersteine, keine Inseln, ein ausgefranster Grasstreifen in der Mitte (`mid_amt`). Andere Wege bleiben pixelgleich (der Zufall wird gleich verbraucht). Bake: `py -3 tools/bake_ground.py --path=caravan_road`, dann `--import`.
- `CaravanRules.road(id)` (Pfad aus ground.json in Weltpixel, gleicher Catmull-Rom wie der Baker), `CaravanManager.route()` = Weg vom fernen Ende bis zur Hütte, dann `walk_route` bis zum Stellplatz (endet exakt auf dem Stellplatz), `pick_slot(.., from)` nimmt den Stellplatz, der dem Wegende am nächsten liegt.
- Zeiten neu: Fahrt 130 s, Ankunft 0,36 (Aufbruch ~0,18, also nach Nachtende), Abfahrt 0,58 (außer Sicht vor 0,78).
- Karte: `CaravanMerchant.map_marker()` (Stil `jorun` in `data/map_markers.json`): „KARAWANE UNTERWEGS" auf dem Weg, „KARAWANE" am Platz, Name erst nach dem ersten Gespräch.
- Test `tools/test_caravan.tscn` jetzt 102 Prüfungen (Weg, Route, Kartenmarke). Bilder: `Godot --rendering-driver opengl3 --path . --fixed-fps 60 tools/preview_caravan.tscn -- --dir=/abs [--night]` (unterwegs, offen, Nacht).

**Schritt 3 (2026-11-13): Wagen und Ochse.**
- `py -3 tools/art_caravan.py [kontakt.png]` (≈ 30 s, Ellipsoid-Renderer aus `art_hero3d.py`; vom Hauptagenten gemacht, das Terra-Modell steht als Subagent nicht zur Verfügung) → `assets/town/caravan/`: `wagon_roll.png` (8 Richtungen × 4 Raddrehungen, 144×108, Füße (72, 90)), `wagon_stand.png` (Zeile 0 nach Osten, 1 nach Westen geparkt; Spalten 0 zu, 1–8 Aufklappen, 9 offen, 10 Nacht), `ox.png` (8 Richtungen × 22: idle 4, walk 8, graze 6, lie 4; 80×64, Füße (40, 54)), je `_glow` (Laternen) und `data/caravan_art.json` (Ablageplätze der Waren auf der Theke, Laterne, Abstand Ochse–Wagen). Der Wagen ist ×1,3 skaliert (Plane deutlich über Kopfhöhe); Stellplätze dafür auf ±62 px gerückt, Fußfläche 80×26.
- Planwagen in Karawanenblau mit Flicken, roter Zierleiste, Messingglocke, Laterne am Bock; hinten zugezogene Plane, vorne gerafft über dem Kutschbock. Offen: die Seitenwand liegt als Theke auf zwei Beinen, die Plane ist zum kurzen Vordach mit Wimpeln und Schild ausgestellt, innen Regal mit Gläsern und Kisten.
- Zottelochse: zotteliges Fell mit Moos, Hörner, Joch mit Glocke und kleiner Laterne.
- `CaravanView`: Sprites statt Platzhalter (Rad dreht mit der gefahrenen Strecke, Aufklapp-Frame aus der Phase, Ochse als eigener y-sortierter Knoten vor dem Wagen: geht, grast, liegt nachts), Waren-Icons auf den Ablageplätzen, `NightLight` an Wagenlaterne und Joch. Ohne die Bilder bleibt der gezeichnete Platzhalter.
- **Nicht gemacht: Jorun selbst.** Figuren, Porträts und Dialogtexte macht laut CLAUDE.md ein eigener Agent; `CaravanMerchant` zeigt die Platzhalterfigur, bis `assets/characters/jorun.png` + `data/jorun_rig.json` (Clips Abschnitt 8.1) da sind.
- `tools/preview_caravan.tscn` setzt vor jedem Bild die Kamera der Spielerin.

**Jorun (2026-11-13, auf Wunsch der Nutzerin vom Hauptagenten gestaltet, nicht vom Figuren-Agenten).**
- `py -3 tools/art_jorun.py [kontakt.png]` (≈ 35 s; `quick out.png` für einen schnellen Blick) → `assets/characters/jorun.png`, `jorun_glow.png` (nur das Laternenlicht), `data/jorun_rig.json` (Siedler-Format 76×96, Füße (38, 80), Höhe 58). Gleicher Ellipsoid-Renderer wie Ellie, Gustav, Torben, Esma, Ilva.
- Aussehen: älterer, breiter Mann; langer erdbrauner Reisemantel offen über einer verblichenen Senfweste mit Messingknöpfen, Saumband und Halstuch in Karawanenblau, Taschengurt quer über der Brust, Beutel am ganzen Gürtel, Umhängetasche; dunkle Hose in Stulpenstiefeln; wettergegerbtes Gesicht, kurzer graubrauner Vollbart, buschige Brauen, dunkelbraune Augen; breitkrempiger Filzhut mit blauem Band, Feder und Schnüren voller Anhänger (Messing, rotes Glas, Feder); Wanderstab mit kleiner Laterne am Haken.
- Clips: idle 4, walk 6, counter 6, arrange 6, count 6, call 6, wave 6, present 6, smoke 6 (52 Frames). Vom Konzept 8.1 weggelassen: drive, climb_down, chock, carry_crate, sit (er geht neben dem Ochsen, statt zu fahren).
- Am Stand (`CaravanMerchant._stall_clip`): Zyklus counter / arrange / count / smoke; winkt der Spielerin beim ersten Nahekommen des Tages, ruft Leuten in 90–190 px etwas zu (Pool `call`, Sprechblase), hält ein Bündel hin, solange sein Handelsfenster offen ist. Unterwegs geht er neben dem Ochsen.
- Noch nicht: Dialogporträt (`assets/ui/portrait_jorun.png`), echte Texte (Dialog-Writer).

**Schritt 4 (2026-11-13): Leben am Stand.**
- Siedler: Spot-Anker `of: "caravan"` (`Settler.spot_position/resolve_spot`, `CaravanManager.customer_point/visitable`): Gustav (0,56–0,60) und Torben (0,56–0,62) verbringen ihre Mittagspause am Stand, solange er steht (Aufbau bis Abfahrt, damit niemand mitten in der Pause springt), sonst am Feuer.
- Chatter (`data/chatter.json`): Reaktionen auf `caravan_arrived` / `caravan_leaving`.
- Krähen: zwei `RoofPerch` auf der Plane (`CaravanView.is_done` = steht), `TownCritters`/`CorvidPopulation` nutzen sie wie Dächer.
- Alarm (`TownManager.fear_on`): Laterne gedimmt, der Ochse steht nachts unruhig statt zu liegen. Sturm schließt den Stand (Schritt 1), Regen-Tropfen am Vordach sind nicht gebaut.
- Töne `py -3 tools/audio_caravan.py` → `assets/audio/caravan/` (bell_a/b, wheels-Schleife, ox_snort, ox_low, ox_bells, flap, cloth, chain, knock; synthetische Platzhalter), abgespielt von `CaravanView._sounds` (Räder beim Fahren, Glocke beim Ein- und Ausfahren, Ochse ab und zu, Klappe/Plane/Kette beim Auf- und Abbau) und beim Klopfen.
- Test `tools/test_caravan.tscn` jetzt 108 Prüfungen.

**Schritt 5 (2026-11-13): Netzwerk.**
- `tools/test_caravan_network.tscn` (zwei Prozesse, Loopback-Port 17905): Host `Godot --headless --path . --fixed-fps 60 tools/test_caravan_network.tscn -- --server`, dann der Client ohne Flag. Der Host gründet die Stadt, baut den Brunnenplatz, gibt die Uhr frei (eine frische Welt hält sie für die Eröffnung an) und holt die Karawane (Fahrt/Aufbau/Abbau im Test verkürzt); der Client tritt spät bei, bekommt den laufenden Besuch mit dem Stadt-Snapshot, sieht den Stand offen auf demselben Stellplatz mit demselben Angebot, kauft ein Stück und verkauft drei Gesucht-Stücke über den Host (Zähler und Geld kommen zurück), dann reist die Karawane ab und ist auf beiden Seiten weg. Beide geben `CARAVAN NETWORK ... PASS` aus.
- Beobachtet: ein Beitretender rechnet die Phase erst richtig, wenn die Uhr des Hosts angekommen ist (Sync alle 2 s); der Test wartet darauf. Godot stürzt beim Beenden headless gelegentlich ab (Segfault nach dem Ergebnis), das ist unabhängig von der Karawane.
