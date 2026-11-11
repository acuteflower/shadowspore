# Questtafel, Ausbau: "Das Gedächtnis der Stadt"

Stand: 2026-11-11. Konzept, noch nichts gebaut. Baut auf `docs/questtafel_konzept.md` auf (Grundsystem steht: Zettel, Fenster, Aushang von außen, Melden beim Auftraggeber). Alle Texte sind Platzhalter für den Dialog-Autor.

## 1. Leitidee

Die Tafel ist kein Zufallsgenerator mehr, sondern das Gedächtnis der Stadt: Sie hängt auf, was die Stadt gerade erlebt hat (Mangel, Sturm, eine schlimme Nacht, Neumond), sie altert sichtbar, sie zeigt schon im Vorbeigehen, ob sich ein Blick lohnt, und sie erinnert sich an das, was man für die Stadt getan hat. Jeder angenommene Zettel ist ab dem Moment ein Quest und lebt im Quest-Ast der HUD und auf der Karte.

Fünf Regeln, an denen alles hängt:
1. **Der Grund steht auf dem Zettel.** Jeder reaktive Zettel trägt ein kleines Warum ("WEGEN DES STURMS", "NEUMOND"), im Fenster, am Papier und im Quest-Ast. Dann spürt man die Reaktion.
2. **Alles Sichtbare ist von außen lesbar.** Neu, alt, eilig, nass, Steckbrief, Ehrungen: am gebauten Brett, ohne Fenster.
3. **Host entscheidet, Peers zeichnen.** Zettel, Fristen, Titel, Belohnung: Host-Zustand wie bisher. Alterung, Wetter, Krähe, Knospe, Ton: rein kosmetisch und lokal (wie `TownCritters`).
4. **Alles in JSON.** `data/board.json` bekommt `occasions`, `age`, `urgent`, `bounty`, `honor`. Neue Anlässe sind Daten, kein Code.
5. **Ein angenommener Zettel ist ein Quest-Eintrag.** Über einen Adapter (siehe 3.1), damit das Quest-System in v0.8 ersetzt werden kann, ohne die Tafel anzufassen.

## 2. Die neun Bausteine, in vier Schichten

| Schicht | Baustein | Kern |
|---|---|---|
| A. Leben | Neu-Signal, Zettel-Alter, Wetter, Krähe | Die Tafel zeigt Zustand und Zeit |
| B. Anlässe | Reaktive Zettel, Eilzettel, Steckbriefe | Die Tafel reagiert auf das Spiel |
| C. Gedächtnis | Ehrentafel, Titel | Die Tafel erinnert sich |
| D. Einbindung | Quest-Ast, Kartenmarker | Die Tafel ist Teil des Questsystems |

### 2.1 Neu-Signal (Schicht A)
- **Die Knospe** an der Tafel (jetzt ein festes Leuchtpixel im Bild) wird zu einer lebenden Knospe, gezeichnet von `BoardNotes` auf dem ungeschatteten Knoten: ruhig = langsamer Atem; **ungelesene Zettel** = schneller Puls, helleres Licht, aufsteigende Mote. Farbe zeigt die dringendste Art: Teal (normal), Gold (Story-Siegel), Rot (Eilzettel oder Steckbrief).
- **Ungelesen** ist pro Spieler lokal: `board_seen` (Liste der Zettel-IDs, im Spielstand gespeichert, bereinigt um verschwundene). Gelesen heißt: Fenster geöffnet, oder 2 s lang im Bild und nah (`reach`) an der Tafel gestanden. Der Zettel bekommt bis dahin ein kleines blinkendes Eckpixel.
- **Fernwirkung:** nachts ein winziges `NightLight` das mit der Anzahl ungelesener Zettel etwas weiter reicht; tagsüber ein feines Funkeln. Man sieht es schon im Vorbeilaufen.
- **Ton** (`py -3 tools/audio_board.py`, synthetisiert, räumlich, hörbar ~200 px): beim Sonnenaufgang rascheln die Zettel nacheinander herein (0,4 s Abstand, je ein leises Anheften "tack"), ein neuer Eilzettel bringt ein kurzes Messingglöckchen, abgenommene Zettel ein Reißen.
- Das einmalige Lernen: `HintCard` beim ersten Zettel ("Neue Zettel erkennst du an der pulsierenden Knospe").

### 2.2 Zettel-Alter (Schicht A)
Der Alterungsgrad ist eine reine Funktion `BoardNotes.stage(offer, tag, tageszeit)`, Bruchteil `f = (jetzt - gehängt) / (läuft ab - gehängt)`:

| f | Stufe | Papier |
|---|---|---|
| 0 – 0,35 | frisch | glatt, hell, scharfe Tinte, perfekter Sitz |
| 0,35 – 0,7 | hängend | Kanten gilben leicht, ein Pixel Welle am unteren Rand |
| 0,7 – 0,9 | alt | merklich gelb (bis +40 % zu `c9a24a`), Eselsohr (2-Pixel-Falte rechts unten), Tinte verblasst |
| 0,9 – 1 | letzter Tag | wie alt, dazu hängt es schief an einer Ecke, Tinte nur noch halb |

Zettel mit Siegel (Story) altern nie. Der Eilzettel altert in einem Tag in Echtzeit-Stufen (frisch bis Mittag, alt am Abend).

### 2.3 Wetter und Wind (Schicht A)
- **Wind:** die Ecken flattern mit `WorldWind` (Böe hebt eine Ecke, im Sturm flattern alle, ein Zettel klatscht gegen das Brett). Heute schon ein zufälliges Kippen; es wird von `g_wind_gust` gesteuert.
- **Regen:** ein lokaler Nässewert `w` (0..1) folgt `WeatherManager.exposure_at(Tafel)` und `rain_now()` (in 25 s nass, in 40 s trocken). Ab `w` 0,3 blaugrauer Ton und ein Pixel Durchhang; ab 0,8 verläuft die Tinte (Striche werden breit, ein Tropfen darunter). Das Dach schützt: leichter Regen nässt nur die untere Reihe, Sturm alles.
- Spielwirkung: keine. Rein Stimmung. Eine Ausnahme sind die Anlässe nach dem Sturm (2.5).

### 2.4 Die Krähe (Schicht A)
Abgelaufene Zettel verschwinden im Zustand sofort (Host, Sonnenaufgang), aber die Anzeige hält sie als lokalen **Geist** (kosmetisch, höchstens 25 s):
- Ist eine Krähe verfügbar (`TownCritters`, Tag, Kamera sieht das Brett, `_watched`), fliegt sie an: neuer Sitz `RoofPerch` auf dem Dach des Bretts, zwei Pickser, sie zieht das Papier ab und fliegt damit davon (3 Papier-Pixel im Schnabel).
- Sonst weht der Wind den Zettel ab: er löst sich und flattert zu Boden.
- Höchstens eine Krähe pro Morgen, ein Zettel pro Besuch. Keine Verzögerung des Spielzustands: Annehmen eines "Geist"-Zettels ist unmöglich.

### 2.5 Reaktive Zettel: "Anlässe" (Schicht B)
Der Host würfelt beim Sonnenaufgang nicht mehr nur aus Vorlagen. Zuerst prüft er **Anlässe**: Bedingungen über einem kleinen Tageskontext `BoardContext` (rein, testbar): Tag, Mondphase, Lagerbestand, Wetter von gestern, Bericht der letzten Nacht. Ein fälliger Anlass reserviert einen der `new_per_day`-Plätze, der Rest bleibt Zufall. Jeder Anlass hat `cooldown_days`, `weight`, einen Auftraggeber (mit `min_trust`) und ein `why`.

| Anlass | Bedingung | Zettel | Warum-Chip |
|---|---|---|---|
| Mangel | Lager < Schwelle bei Holz/Stein/Faser (aus `TownManager.stock`) | Gustav bittet um genau die Lücke (Menge skaliert), Aufschlag 20 % | "DAS LAGER IST LEER" |
| Nach dem Sturm | Wetterzustand `storm` gestern | Gustav: Holz und Faser fürs Flicken, Eil-fähig | "WEGEN DES STURMS" |
| Nach der Nacht | Nacht hatte einen Vorstoß oder Wesen im Lichtrand; Bericht nennt Sektor und Art | Valdric: "räumt den [Nord]rand", Jagd auf die Art, Anzahl ~ Zahl der Eindringlinge, Einsatzgebiet auf der Karte (der Sektor) | "NACH DEM VORSTOSS" |
| Neumond | `moon_phase()` ist 0 (Abend davor) | Valdric: **Nachtjagd**, zählt nur in genau dieser Nacht, 1,5-facher Lohn | "NEUMOND" |
| Vollmond | Phase 4 | Esma: nachtblühende Pflanzen sammeln (Mondglocke, Nebellilie), Bonus | "VOLLMOND" |
| Feuchte Tage | Regen zwei Tage | Esma: Pilze (Glimmkappe, Morchel) | "ES HAT GEREGNET" |

Weitere Anlässe sind Zeilen in `data/board.json`. Der Chip ersetzt keinen Text, er ist der kleine Beleg, dass die Stadt reagiert.

### 2.6 Eilzettel (Schicht B)
Ein Zettel mit rotem Wachssiegel (ungeschattet, pulsiert schneller, ein Glöckchen beim Aufhängen):
- **Frist bis Sonnenuntergang** des gleichen Tages (Uhr, nicht Tage), im Quest-Ast als Ring um die Knospe, der abnimmt und im letzten Fünftel rot flackert.
- **Doppelter Lohn** (Kupfer, XP), doppeltes Vertrauen, **das Extra-Item ist sicher**.
- Höchstens ein Eilzettel hängt zur Zeit. Er entsteht aus Anlässen mit `urgent` (Sturmschaden, Brand-Mangel) oder mit kleiner Chance durch Aufwertung einer Beschaffen-Vorlage (`urgent.upgrade_chance` 0,12, ab Vertrauen 20).
- Es gibt keine Strafe fürs Verpassen, nur den Verlust (ein Gefühl wie "zu spät"). Der Auftraggeber sagt beim nächsten Ansprechen eine kurze Zeile.
- Warum es eine Entscheidung ist: die Frist endet vor der Nacht, also kostet der Eilzettel den Tag.

### 2.7 Steckbriefe und Gezeichnete (Schicht B)
Ein Steckbrief ist ein größeres Papier an einem eigenen Platz links am Pfosten (höchstens einer), mit einem gezeichneten Schattenriss des Wesens (Tintenskizze), Namen und Kopfgeld.
- **Gezeichnete:** überlebt ein Elite (`night.json` `elite`, derzeit Leerenbrecher) die Nacht und flieht beim Morgengrauen (heute verbrennt er ohne Beute), merkt sich `NightDirector` ihn als *Gezeichneten* (Name aus `bounty.names`, Narbe, +10 % Leben je überlebter Nacht, höchstens +30 %). Am nächsten Morgen hängt sein Steckbrief. In einer späteren Nacht kehrt er als Elite zurück, mit Namen. Er bleibt, bis er fällt.
- **Zählen:** der Steckbrief zählt für jeden Spieler, der ihn angenommen hat **und den Gezeichneten getroffen hat** (der Host führt dafür die Trefferliste am Wesen), nicht nur für den letzten Schlag. Das ist fairer im Koop.
- **Belohnung:** Kopfgeld (hoch), XP, sicherer seltener Gegenstand (`bounty.loot`), Vertrauen bei Valdric. Der Name steht danach in der Ehrentafel.
- **Mini-Bosse später:** ein dauerhafter Steckbrief (Mornath) nutzt dasselbe Papier und führt über die Arena-Markierung. Heute nicht Teil des Plans.
- Kunst: `tools/art_board_posters.py` zeichnet drei Tintenskizzen (Spinne, Lauscher, Brecher) aus den vorhandenen Silhouetten, plus Wachs und Randzeichen.

### 2.8 Ehrentafel und Titel (Schicht C)
- **Das Dankband:** unter dem Brett hängt eine Schnur, an der für jeden erledigten Zettel der Stadt ein kleiner Dankeszettel pendelt (die letzten 12 sichtbar, der neueste schwingt noch). Sie wachsen nicht nach oben, sie hängen: die Tafel sieht erlebter aus.
- **Zähler:** Stadt (alle Spieler) und je Spieler: erledigt gesamt, nach Art (Beschaffen, Jagd, Eil, Gezeichnete), nach Auftraggeber.
- **Fenster:** dritter Reiter EHRENTAFEL: "37 AUFTRÄGE ERLEDIGT", die Zähler als Federstrich-Reihen, die Titel, die man trägt.
- **Titel** (nur kosmetisch, im Fenster und in der Stadtseite, Platzhalter): HANDLANGER (5), VERLÄSSLICH (15), RÜCKGRAT DER STADT (40), DUNKELRÄUMER (30 Jagdkills über die Tafel), EILBOTE (5 Eilzettel), NAMENSJÄGER (1 Gezeichneter), JEDERMANNS FREUND (je ein erledigter Zettel für jeden Bewohner).
- **Die Tafel wächst:** bei 25 / 50 / 100 erledigten Stadt-Zetteln hängt `limits.simple` um 1 höher (bis die 6 Plätze belegt sind) und an der Tafel erscheint eine kleine Laterne, dann ein zweites Dach-Schindelpaar, dann ein Ehrenschild. Kosmetik plus ein klein wenig Auswahl.

## 3. Einbindung

### 3.1 Der Quest-Ast als Adapter (Schicht D, wichtigste Naht)
`QuestComponent.current()` kennt heute nur *den ersten* laufenden Quest, HUD und Karte zeigen nur ihn. Statt das jetzt umzubauen (in v0.8 überarbeitet), kommt eine dünne Naht:

- **`TrackedQuests`** (`src/systems`, Kind des Spielers, nur lokal): `entries()` liefert eine Liste von Einträgen im Format von `current()`, erweitert: `{id, source: "story"|"board", kind, title, text, step, steps, target, search, tasks, progress {have, need}, deadline {day, time, urgent}, why, tone}`. Story zuerst (`QuestComponent.current()`), danach Zettel aus `BoardManager.tracked(peer)`.
- **`QuestVine`** liest `entries()` statt `current()`: der Hauptzweig wie bisher; darunter bis zu **drei Nebenzweige** (Knospe, Kurztitel, "7/12", Entfernung; Farbe nach Art; Eilzettel mit Fristring). Gibt es keinen Story-Quest, wird der erste Zettel selbst der Hauptzweig mit vollem Text. Überzählige: "+2". Neu angenommen: wächst heraus; erledigt: Aufblitzen, welkt.
- **`MapWindow`** zeichnet alle Einträge (siehe 3.3).
- **Verfolgen:** im Reiter ANGENOMMEN schaltet E (Knopf VERFOLGEN) einen Zettel für Ast und Karte; Voreinstellung: die drei jüngsten.
- **Folgen für v0.8:** der Adapter ist der einzige Ort, der Story- und Zettelquests kennt. Das neue Questsystem liefert dieselbe Eintragsliste; die Tafel bleibt unberührt. Ereignisse (`quest_started/step/finished` mit `board:<id>`) laufen zusätzlich über `EventBus`, damit Journal und Erfolge später dran hängen können.

### 3.2 Persönliche Frist
Heute verschwindet ein angenommener Zettel mit seinem Aushang. Das passt nicht zu "ein Zettel ist ein Quest". Neu: ein angenommener Zettel bekommt eine **persönliche Frist** = Ablauftag des Zettels, aber **mindestens zwei Tage ab Annahme**. Danach verfällt er für diesen Spieler leise (Auftraggeber sagt kurz etwas). Eilzettel behalten die Uhrfrist.

### 3.3 Kartenmarker
`MapWindow._draw_quest` zeichnet heute eine goldene Blüte für den ersten Quest. Neu für jeden Eintrag, in der Farbe nach Art:

| Art | Marker |
|---|---|
| Story | wie bisher, goldene Blüte |
| Beschaffen, noch nicht fertig | **Fundbereich**: gestrichelter Umriss des Gebiets, in dem es wächst (Auswahl über `board.json` `hints`: Gebiet/Superregion, Fluss, Küste), kein Punkt; fehlt der Hinweis, zeigt die Karte nichts |
| Beschaffen, fertig | der Auftraggeber (folgt dem Siedler wie ein `actor`), Wort "MELDEN" |
| Jagd | Einsatzgebiet (Sektor aus dem Nachtbericht) als Kreis; bei Neumond-Nachtjagd kein Marker, nur die Nacht-Zählung im Ast |
| Eilzettel | rot, mit Fristring |
| Steckbrief | magenta Fadenkreuz am letzten Sichtort (Suchkreis 40 m); ist der Gezeichnete geladen und nah, folgt der Marker ihm wie ein `PetGlint` |

Im Ast steht dazu die Entfernung (Meter = Kacheln), wo es einen Marker gibt.

## 4. Datenskizze (`data/board.json`)

```
"age": {"stages": [0.35, 0.7, 0.9], "yellow": 0.4},
"personal": {"min_days": 2},
"urgent": {"copper": 2.0, "xp": 2.0, "trust": 2.0, "bonus_chance": 1.0, "until": "dusk", "max_hanging": 1, "upgrade_chance": 0.12, "min_trust": 20},
"occasions": [
  {"id": "low_wood", "when": {"stock_below": {"wood": 20}}, "giver": "gustav", "template": "gustav_wood",
   "scale": {"count": "gap", "pay": 1.2}, "why": "DAS LAGER IST LEER", "cooldown": 3},
  {"id": "after_storm", "when": {"weather_yesterday": "storm"}, "giver": "gustav", "template": "gustav_wood",
   "urgent": true, "why": "WEGEN DES STURMS", "cooldown": 6},
  {"id": "after_raid", "when": {"night_report": "intruders"}, "giver": "valdric", "kind": "kill",
   "species": "from_report", "area": "report_sector", "why": "NACH DEM VORSTOSS"},
  {"id": "new_moon_hunt", "when": {"moon": 0, "at": "dusk_before"}, "giver": "valdric", "kind": "kill",
   "window": "night", "scale": {"pay": 1.5}, "why": "NEUMOND"}
],
"bounty": {"names": ["DER KLOTZ", "BRECHER VOM RAND"], "health_per_night": 0.1, "max_nights": 3, "loot": "void_slag"},
"honor": {"milestones": [25, 50, 100], "titles": [{"id": "handlanger", "need": {"done": 5}}]},
"hints": {"moonbell": {"area": "super:nebelwald"}, "fish_eel": {"area": "water"}}
```

Neue Notizfelder: `u` (eilig), `w` (Warum), `a` (Gebiet), `win` (Zeitfenster), `bn` (Gezeichneter), `due` (persönliche Frist je Eintrag).

## 5. Netzwerk, Speichern, Tests

- Host-Zustand: `offers`, `taken`, Zähler (`honor`: Stadtsumme, je Spieler, im Spieler-Block der Titel), `marked` (Gezeichnete, im Nachtzustand von `NightDirector`).
- Lokal/kosmetisch: Alter, Wetter, Knospe, Krähe, Ton, `board_seen`.
- Neue Tests: `tools/test_board.tscn` erweitert um Alterungsstufen, persönliche Frist, Anlass-Auswahl (Lager, Sturm, Nacht, Mond, Cooldown), Eilzettel-Aufwertung und Frist, Treffer-Liste des Gezeichneten, Zähler und Titel, `TrackedQuests`-Ordnung; Vorschau `tools/preview_quest_board.tscn` mit `--aged`, `--rain`, `--eil`, `--poster`.

## 6. Der Plan in drei Schritten

### Schritt 1: Die Tafel lebt und ist Teil der Quests
**Status: gebaut (2026-11-11)**: `TrackedQuests` (src/systems/tracked_quests.gd, Kind des Players, Speicher `board_local` {seen, untracked}), `QuestVine` mit bis zu drei Nebenzweigen, `MapWindow._draw_board_marks`, VERFOLGEN im Fenster, persönliche Frist (`personal.min_days`, abgelaufene Zettel bleiben in `offers`, solange sie jemand trägt, hängen aber nicht mehr: `BoardManager.hanging()`), `BoardNotes` neu (Alter in vier Stufen, Wind, Nässe, lebende Knospe `BUD` mit `beacon` {unread, story}, Eckpixel, Geist-Zettel, Krähe zieht ab / Wind weht weg, feste Plätze), `TownCritters.board_visit` (Krähe am Dach), `TownStructure.attention` (Fernlicht), `HintCard.notify_board`, Klänge `py -3 tools/audio_board.py`. Test `tools/test_board.tscn`. Nicht umgesetzt: der Klang `wet` wird noch nicht abgespielt, Jagd-Zettel haben keinen Kartenmarker.
Ziel: sichtbare Wirkung und die Naht für v0.8. Kein neuer Spielinhalt außer der persönlichen Frist.
- `TrackedQuests` + `QuestVine` (Nebenzweige, Hauptzweig-Rolle) + `MapWindow` (Marker: Auftraggeber bei "fertig", Jagd ohne Marker erst einmal), VERFOLGEN-Knopf.
- Persönliche Frist (3.2) und der Abgang einer Frist.
- Neu-Signal: lebende Knospe, `board_seen`, Fernlicht, Eckpixel, `HintCard`.
- Alter (frisch bis letzter Tag), Wind, Regen/Nässe.
- Die Krähe plus Geist-Zettel, `RoofPerch` auf dem Brettdach.
- `tools/audio_board.py` (Rascheln, Anheften, Reißen, Nass).
- Fertig, wenn: ein angenommener Zettel im Ast und auf der Karte steht, die Knospe pulsiert und nach dem Lesen ruht, Zettel sichtbar altern, nach Regen aufweichen, und eine Krähe einen abgelaufenen abzieht. `tools/test_board.tscn` grün, neue Vorschau-Schalter.
- Aufwand: mittel bis groß (Adapter und Ast sind der Brocken).

### Schritt 2: Die Stadt spricht
**Status: gebaut (2026-11-11)**: `BoardRules.due_occasions/make_occasion` (rein) mit den sechs Anlässen aus `data/board.json` `occasions` (Mangel, Nach dem Sturm, Nach dem Vorstoß, Neumond-Nachtjagd, Vollmond, Feuchte Tage), `BoardManager.context(day)` / `post_occasions(ctx)` (Anlässe belegen zuerst bis zu `limits.occasions` Plätze von `new_per_day`, Cooldown je Anlass `occasion_last`, gespeichert als `occ`), `NightDirector.last_night_report()` (wer bis 48 px an den Lichtrand kam: Anzahl, häufigste Art, Himmelsrichtung, Mittelpunkt; gespeichert), Eilzettel (`u`/`ut`: Uhrfrist bis 0.80, doppelter Lohn, sicheres Extra, höchstens einer, Aufwertung 12 % ab Vertrauen 20, `BoardManager.check_rush` entfernt ihn mit den Einträgen), Warum-Chip im Fenster, rotes Wachs und Glöckchen an der Tafel, Fristring im Ast, Karte: Einsatzgebiet (rot) und Fundgebiet (gold, `hints`), Nachtjagd zählt nur nachts (`win`). Test `tools/test_board.tscn`. Nicht umgesetzt: Fundgebiete nur für Mondglocke/Nebellilie, Wasser-Hinweise fehlen, Vorschau-Schalter `--eil`.
Ziel: die Tafel reagiert auf das Spiel.
- `BoardContext` und die `occasions`-Auswahl (Reservierung von Plätzen, Cooldown, Warum-Chip in Fenster, Papier und Ast).
- Anlässe: Mangel, Nach dem Sturm, Nach der Nacht (braucht `NightDirector.last_night_report()`), Neumond-Nachtjagd (Zeitfenster), Vollmond, Feuchte Tage.
- Eilzettel: Siegel, Glöckchen, Uhrfrist (Ring im Ast), doppelter Lohn und Extra-Item, Aufwertung.
- Karte: Fundbereiche (`hints`) und Einsatzgebiete (Sektor des Berichts), Eil-Markierung rot.
- Fertig, wenn: ein Sturm am nächsten Morgen einen Sturmzettel hängt, eine Nacht mit Vorstoß einen Rand-Zettel, Neumond eine Nachtjagd; ein Eilzettel mit Uhr den Tag formt. Tests für jeden Anlass und die Frist.
- Aufwand: mittel.

### Schritt 3: Das Gedächtnis
**Status: gebaut (2026-11-11)**: *Gezeichnete* in `NightDirector` (`marked` {name, species, nights, pos, day}, gespeichert im Nachtzustand): ein Elite (`elite`-Eintrag in `_live`), der den Morgen erlebt, verbrennt nicht mehr, sondern flieht 7 s (`bounty.flee_seconds`) und wird gemerkt (`_survive`, Name aus `bounty.names`, `nights` +1 bis `max_nights` 3); in einer späteren Elite-Nacht (immer bei Neumond, sonst `return_chance` 0.6, einmal je Nacht gewürfelt, `_elite_due`) kehrt er mit Namen und +10 % Leben je Nacht zurück (`_spawn_elite`), `_track_marked` hält seinen Ort. Die Trefferliste liegt am Wesen (`HealthComponent.hitters`, Host). *Steckbrief* = ein `kill`-Zettel mit `bn`/`bh` (`BoardRules.make_bounty`, nie ablaufend, Lohn wächst je Nacht, sicherer Zusatz `void_slag`, `a` = letzter Ort, Radius 40 m), `BoardManager.check_bounty()` hängt ihn morgens auf (höchstens einer, zählt nicht für die einfachen Plätze und nicht für den einen Zettel je Auftraggeber), schiebt den Ort nach (alle 6 s, ab 32 px) und zahlt beim Fall alle, die ihn je getroffen haben (`_on_bounty_fell`: Eintrag auf 1, wer ihn nie traf wird entlassen, der Zettel hängt nicht mehr). Die Jagdzähler `note_kill` ignorieren Steckbriefe. Karte: magenta Fadenkreuz + Suchkreis (`TrackedQuests` `bounty`, `area_name` ZULETZT GESEHEN, `MapWindow._draw_notice_area`). *Ehrentafel*: `BoardManager.honor` {town, peers, titles, fallen} (Zähler nach Art/Auftraggeber, Namen der Gefallenen, gespeichert, nur der eigene Spieler im Save), Reiter EHRENTAFEL (Titel mit Fortschrittsbalken, TRAGEN/ABLEGEN, Gefallene), sieben Titel in `data/board.json` `honor.titles` (`BoardRules.title_*`, rein), Titel und Zahl in der STADT-Seite, Meilensteine 25/50/100 geben dem Brett einen einfachen Zettel mehr (`_simple_cap`) und lassen es wachsen (Laterne, zweites Schindelpaar, Ehrenschild); `BoardNotes` zeichnet den Steckbrief (eigener Platz über dem linken Pfosten, Tintenskizze je Art, Strichliste der Nächte, Wachs) und das Dankband (letzte 12, der neueste schwingt) im Code. Test `tools/test_board.tscn`, Vorschau `tools/preview_quest_board.tscn -- --poster=void_crusher --nights=2 --honor=60 [--night]`. **Abweichungen:** keine eigene `art_board_posters.py` (Skizzen sind kleine ASCII-Bitmaps in `BoardNotes.SKETCH`), der Titel steht nicht auf dem Dankzettel (nur Fenster und Stadtseite); Mini-Bosse bleiben ausgeklammert.
Ziel: Spitzen und Rückblick.
- Gezeichnete im `NightDirector` (Merken, Namen, Rückkehr, Trefferliste am Wesen), Steckbrief-Papier und -Kunst (`art_board_posters.py`), Kartenmarker (Fadenkreuz, folgt dem Wesen).
- Ehrentafel: Zähler (Stadt/Spieler), Dankband an der Tafel, Reiter EHRENTAFEL, Titel, Meilensteine (Tafel wächst).
- Abschluss: Balance (Lohn Eil/Steckbrief), Feinschliff, Vorschau- und Capture-Sätze, Doku und `CLAUDE.md`.
- Fertig, wenn: ein überlebter Elite am nächsten Morgen einen Steckbrief bekommt und er nach seinem Fall in der Ehrentafel steht; Titel erscheinen; die Tafel bei 25 erledigten Zetteln sichtbar wächst.
- Aufwand: groß (Nachtsystem-Hook und Kunst).

## 7. Entscheidungen (2026-11-11)

1. **Persönliche Frist:** mindestens zwei Tage ab Annahme. Entschieden.
2. **Steckbrief-Treffer:** jeder, der angenommen und den Gezeichneten getroffen hat. Entschieden.
3. **Gezeichnete:** erst ab der Stufe "flut" (Nacht 12), wo der Elite auftritt. Entschieden; eine frühere Regel kann später dazukommen.
4. **Titel:** Vorschlag, noch offen: reine Kosmetik, man wählt einen aktiven Titel. Zu sehen im Fenster (Ehrentafel), in der STADT-Seite und als Zeile auf dem Dankzettel; nicht über dem Kopf, solange es keine Namensschilder im Koop gibt.
5. **Ton:** Glöckchen und Reißen sind Platzhalter bis zur Sound-Runde. Entschieden.

## 8. Bewusst nicht in diesem Plan

Siedler heften ihre Zettel selbst an, Handschrift je Siedler, Koch-/Angel-Zettel, Zettelketten und Gemeinschaftszettel mit gemeinsamem Balken. Die Adapter-Naht (3.1) und `occasions` lassen alle später zu.

## 9. Nur Bekannte hängen Zettel aus (2026-11-11)

Die Tafel nimmt nur Zettel von Leuten, die die Spielerin schon kennt: `TownManager.has_met(id)` ist wahr, wenn einmal mit der Person gesprochen wurde (`talked >= 0`), für den Gründer (Valdric) und für Siedler, die die Geschichte bringt (`arrive.story`, Gustav). Wer nur im Siedlerbuch steht (Checkpoint-Sprung, `away`-Hexen wie Esma und Ilva vor dem ersten Besuch), hängt weder einfache Zettel (`BoardRules.roll` bekommt `met_residents()`), noch Anlässe, Eil-Upgrades oder Steckbriefe aus. Ein Geschichtszettel (z. B. `lake_witch_notice`) bleibt als Gerücht bestehen, nennt aber bei unbekanntem Geber "UNBEKANNT" statt des Namens (Tafelfenster und Questast).
