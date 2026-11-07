# Stadt-Ausbau – Konzept „Glimmrast wird lebendig"

Status: **Konzept, nichts gebaut** (Stand 2026-11-07). Grundlage: Analyse der Stadt (`docs/town.md`). Dieses Dokument legt fest, **was jetzt umgesetzt wird**, wie es an die bestehenden Systeme anknüpft und in welcher Reihenfolge gebaut wird. Alles, was nicht hier steht, steht in Abschnitt 9 („Später").

## 0. Umfang

Jetzt umsetzen (Nummern aus der Ideenliste):

| # | Feature | Kurz |
|---|---|---|
| A2 | **Stadtbanner als Mechanik** | Standarte als frei stellbares Teil; Banner an der Hütte wachsen mit der Stadtstufe |
| A5 | **Festgetretener Boden** | Wo viel Betrieb ist, wird der Boden Erde; wo nichts ist, wächst Gras zurück |
| A6 | **Gebäude altern und werden gepflegt** | Efeu, Moos, Blumen, Anstrich; Pflege hängt an Bewohnern |
| A7 | **Nachtlichter** | Hoflaternen, Fensterschein, Glühwürmchen an Lagern, Werkstatt, Pfosten |
| B8 | **Bank zum Hinsetzen** | E auf der Bank; Siedler setzen sich daneben |
| B9 | **Lichtpfosten anzünden und pflegen** | kalt → anzünden → brennt mit Vorrat → nachfüllen |
| B13 | **Klappen an Lager und Werkstatt** | Marktstand-Klappe, öffnet am Tag, schließt in der Nacht |
| C15 | **Abendfeuer als Ritual** | Siedler und Spielerin sitzen in der Feuerrunde, Wärme-Bonus |
| C16 | **Siedler reagieren aufeinander und auf die Stadt** | Gespräche am Feuer, Reaktionen auf Bauten, Stufen, Nächte |
| C19 | **Stadt als Ort auf der Karte** | Flagge, Name, Lichtkreis, Gebäudesymbole; Name beim Betreten |
| C20 | **Nachtschutz sichtbar** | Lichtrand, Funken beim Zurückdrängen, Valdric hält den Rand |

**Nicht jetzt:** Deko-Kategorie (A1), Wappen und Stadtfarbe (A3), Zaun-Varianten (A4), Briefkasten/Glocke, Brunnen/Kochstelle, Feste, Tiere, neue Siedler, Felder, Verteidigungsbauten, Karawane. Wo ein Feature einen Haken für eines davon braucht, steht es als „Haken für später".

## 1. Leitplanken

- **Host-autoritativ, Siedler bleiben reine Funktionen.** Neuer geteilter Zustand wird klein gehalten, vom Host entschieden, in `structures` oder einem kleinen Stadtfeld gespeichert, beim Beitritt im Snapshot mitgeschickt. Was sich aus Uhr und Daten ableiten lässt (Alter, Boden, Gespräche), wird auf jedem Peer gleich **berechnet**, nicht gesendet.
- **Licht ist Land bleibt unberührt.** Bau-Reichweite (`TownManager.circles()`) hängt nur an fertigen Teilen. Nur die **Nacht-Fragen** (`lit_circles()`, `light_depth()`, `spawn_blocked`) kennen künftig ausgebrannte Lampen (B9).
- **Daten in JSON**, Bilder aus den Generatoren (`tools/art_town.py` und Verwandte), danach `Godot --headless --import`. Neue Teile/Overlays sind Einträge in `data/town.json`.
- **Kunst** für Neues: ein `gpt-6.1-terra`-Subagent für die Bilder (Projekt-Regel); Systeme, Einbindung und Prüfung bleiben beim Hauptagenten. Zustandsbilder (Efeu, Klappe, Laternen) folgen dem vorhandenen Muster `art_town.part()` + `INFO` für `at`/`frame`.
- **Bestehende Tests bleiben grün:** `test_town_rules`, `test_town`, `test_town_story`, `test_town_critters`, `test_night`, `test_town_jump`, Netzwerk `test_town_network`.
- Hinweis zur Arbeitskopie: mehrere Shader (`ground_tone`, `night_fog`, `night_moon`, `meadow_details`) sind unbestätigt geändert. A5 und C20 berühren sie: vorher Stand klären, nur einzelne Dateien tauschen, kein Gesamt-Stash.

## 2. Gemeinsame Bausteine (Phase 0)

1. **Struktur-Zustand `u`** (`structures[id]`): kleines Dictionary für Zustände einzelner Bauten, zunächst `{"f": Vorrat 0..1000, "l": 0/1}` für Lichtpfosten (B9). Der Klappenstand (B13) ist **nicht** gespeichert, er folgt rein aus Uhr und Anwesenheit. Fehlt `u` (alte Saves), gilt Standard: Lichtpfosten = angezündet, voll (kein Bruch für bestehende Städte). Speichern/Snapshot: `TownManager.export_state/import_state`, `_rpc_snapshot`.
2. **Stadt-Ereignisse** (`TownManager.event(kind, data)`, Signal `event`): vereinheitlicht, was Siedler und Banner wissen müssen: `built(piece)`, `level_up(id)`, `resident_joined`, `raid_warning`, `raid_start`, `raid_end`, `night_survived`, `lamp_out`. Quellen sind vorhandene Signale und `NightDirector`. Wird nur gemeldet, nicht gespeichert; C16 und C19/C20 hören mit.
3. **Stadt-Zeitrahmen** (reine Hilfen in `TownRules`): `evening_window()` (Feuerzeit), `dusk_amount()`; vermeiden doppelte Konstanten in Settler, Lampen, Klappen.
4. **Sitz-Basis** (B8, C15): `CampfireSeat` wird in `SeatSpot` (Basis: `seat_position`, `approach_position`, `sit_direction`, `occupied`, E-Prompt) und `CampfireSeat extends SeatSpot` aufgetrennt. `RestComponent` nimmt `SeatSpot`.

## 3. A – Dekoration

### A2 Stadtbanner als Mechanik
**Wirkung:** Die neuen Seitenbanner werden Teil des Stadtgefühls statt Einzeldeko.
- **Standarte** (`banner_post`, Kategorie WOHNEN): freistehender Mast (Fuß 8×6, kleine Kollision) mit Querstange und hängendem Banner im bestehenden Design (Teal, Goldstreifen, Schwalbenschwanz), Bild als eigener Wind-Teil (`parts` + `sway`). Kosten ~2 Holz, 1 Faser; `worth` 1; `snap` 8. Kein Funktionswert, aber: **in der Nähe einer Standarte gilt der Ort als „Platz"** (Haken für A5: höhere Betriebs-Gewichtung und für C16: Treffpunkt-Spot).
- **Hütte wächst mit der Stadt:** Stufe `camp`/`hamlet` = ein Banner rechts (wie jetzt); `village` = zweites, spiegelbildliches links am Dachfirst; `borough` = zusätzlich eine kleine Fahne auf dem First neben dem Windanzeiger; `town` = Doppelbanner. Umsetzung in `Hut` (`_banners`) über `TownManager.level` und `event(level_up)`, mit Einblenden (kurz herabrollen) beim Aufstieg.
- **Lager und Werkstatt** behalten ihr Seitenbanner. Haken für später (A3): Banner nimmt Stadtfarbe/Wappen als Shader-Palette.
- **Art:** Standarte (3D-Modell, `art_town.py`), Fahne für den First, zweites Hütten-Banner (gespiegelt, `hut_outside`).
- **Daten:** `town.json` Teil `banner_post`; `Hut.BANNER_BY_LEVEL`.
- **Test:** `test_town` (Teil setzen/abreißen), neuer Check „Banneranzahl je Stufe".

### A5 Festgetretener Boden
**Idee:** Eine Stadt sieht man am Boden. Rund um Türen, Trittplatten, Bänke, Feuer und Wege wird die Wiese zu Erde; verlassene Ecken wachsen zu.
- **Berechnung (rein, überall gleich):** `TownWear` (neu, `src/town/town_wear.gd`, reine Funktionen) liefert für jede 8-px-Zelle einen Wert 0..1 aus: Gewicht der Bauten (Türzone und Standorte der Siedler hoch, Bank/Standarte/Lampe mittel, Zaun gering), Wege (`paths` vorhanden), Trittplatten, **Alter** seit `b` (wächst über 6 Tage), und Abnahme zu den Rändern. Abgerissene Bauten lassen ihren Wert, **verlieren ihn aber in 6 Tagen** (Gras kommt zurück), `TownManager.cleared` bleibt unverändert.
- **Anzeige, drei Schichten:**
  1. **Boden-Shader:** `ground_tone.gdshader` bekommt ein Global `g_town_wear` (Textur, 128×128 Zellen um die Stadtmitte, `g_town_wear_origin`): weniger Halme, Grün wird zu trockener Erde, Rand dithert. Die vorhandenen `_pad`-Bilder bleiben für große Teile.
  2. **Kleinpflanzen:** `MeadowDetails` und Klee verwerfen Punkte, deren Zelle `wear > Schwelle` (Hash pro Punkt, damit der Rand franst), beim Laden des Chunks und bei Änderungen (Fade-out statt Aufploppen).
  3. **Props:** keine Änderung; weiche Props unter Fundamenten bleiben wie bisher geräumt.
- **Aktualisierung:** Textur wird beim Setzen/Abreißen und einmal je Spieltag neu gebaut (dirty-Flag), nur wenn der lokale Spieler in der Stadt ist. Kein Netzwerk: jeder Peer rechnet aus `structures`, `paths`, `b`, `TimeManager.day`.
- **Haken für später:** echte Trittzähler (Spieler/Siedler) und Regen/Matsch.
- **Risiken:** Shader-Globals und Samplergröße; ground_tone ist gerade fremd verändert (Abschnitt 1). Rückfall ohne Shader: nur Schicht 2 plus Decals.
- **Test:** `tools/test_town_wear.tscn` (reine Zellwerte, Abnahme beim Abriss, Chunk lädt ohne Gras auf Zellen mit Wert > Schwelle); Vorschau `preview_town.tscn -- --aged`.

### A6 Gebäude altern und werden gepflegt
**Idee:** Zwei Spuren: **Alter** (Tage seit `b`, gibt es schon als `wear`) und **Pflege** (ist der Bau bewohnt/gepflegt?).
- **Alter:** Efeu an der Wand (Tag 4, Tag 9, wächst von der Ecke), Moos auf der Dachkante (ab Tag 12, schwächer wenn gepflegt), Anstrichspuren (Hütte: Fensterläden verblassen ab Tag 10). Daten: `wear` bekommt `track: "age"` (Standard).
- **Pflege** (`track: "care"`): bewohnte Bauten (Siedler mit `home` dort, Vertrauen ≥ 20) zeigen Blumenkasten an Werkbank-Wand/Regal, frisch gestrichene Kante, Kerze im Fenster; **unbewohnte** oder leere Bauten sammeln stattdessen Spinnweben und mehr Moos. Hütte zählt als bewohnt, wenn Valdric da ist (immer).
- **Mechanik:** `TownStructure._update_wear` zeigt Overlays, wenn `days >= x` **und** `track` passt; Wechsel mit Staubpuff (wie jetzt). Pflege wird aus `TownManager.residents` und `trust` berechnet, nichts Neues im Netz.
- **Art:** je Gebäude 3–4 Overlay-Sheets in `art_town.py` (`wear_*`-Muster) und `art_hut_fresh.py` (Efeu, Moos, Blumen, Spinnweben) als volle Frames mit `_glow` nur wo nötig.
- **Haken für später:** Anstrich-Farbe nach Stadtfarbe (A3); Pflege als Aufgabe (Putzen mit E).
- **Test:** `test_town_critters`-Muster; Check: Overlay-Satz je Alter/Pflege, Saves ohne `b` bleiben konsistent.

### A7 Nachtlichter
**Idee:** Nachts soll jedes Gebäude warm wirken, nicht nur die Hütte und der Pfosten.
- **Lager:** zwei Frontlaternen an den Dachpfosten (zusätzlich zur Innenlaterne), warmer Lichtfleck vor dem Eingang.
- **Werkstatt:** Laterne an der Frontkante; die Schmiede bleibt Hauptlicht und folgt weiter der Anwesenheit des Siedlers.
- **Hütte:** Laterne neben der Tür vorhanden; ergänzen: Dachfenster-Glut je nach Kamin (nur Optik), Licht unter dem Vordach.
- **Glühwürmchen:** Lichtpfosten, Bänke und Standarten bekommen `fireflies` (Gruppe `flora_glow`, nachts sammeln sich Tiere). Der Lichtpfosten hat den Eintrag schon an der Laterne; prüfen und auf Bank/Standarte ausweiten.
- **Technik:** neue `parts` mit `glow` (ungelittener Streifen), kleines `NightLight` je Laterne, `spill`-Bild (Muster `hut_lib.pool_spill`). Laternen brennen nachts automatisch (rein optisch, **zählen nicht** für `lit_circles`, damit B9 die einzige Nacht-Quelle für Schutz bleibt).
- **Art:** `art_town.py`: `lantern()` gibt es, nur neue Positionen und Spills; Hütte in `hut_outside`/`hut_fx`.
- **Test:** Vorschau `--night`; Check: kein Zuwachs in `lit_circles()`.

## 4. B – Interaktion

### B8 Bank zum Hinsetzen
- **E auf der Bank** → `RestComponent.request_sit(seat)` mit der bestehenden Sitz-Animation (acht Richtungen) und Aufstehen mit E oder Bewegung.
- **Sitzplätze:** je Bank zwei Plätze (±8 px), Daten `seats: [[x, y, sektor]]` am Teil; Spiegeln (`f`) vertauscht und spiegelt Sektor. Vor dem Bau prüfen, zu welcher Seite die Bank offen ist (Rückenlehne im Modell `bench()`), Sektor danach wählen.
- **Umsetzung:** `TownStructure` erzeugt je Platz einen `BenchSeat extends SeatSpot` (Prompt „HINSETZEN", belegt, wenn Spieler oder Siedler dort sitzt); `occupied()` prüft Siedler wie beim Feuer.
- **Wirkung:** sitzen ohne Nutzen wäre nur Geste. Entscheidung: **sanfte Erholung** (Ausdauer schneller, Leben 0,4/s bis 70 %) nur im Licht der Stadt (`light_depth > 0`); Zahlen in `data/town.json` `rest`.
- **Siedler:** Gustavs Spot `bench` nimmt den nächsten freien Platz (`resolve_spot`); ohne `sit`-Clip steht er daneben, bis der Art-Agent ihn liefert (bleibt wie in `town.md`).
- **Haken für später:** Bank mit Gesprächs-Spot (C16), mehrere Sitztypen.
- **Test:** `test_town` (Prompt, belegt, Aufstehen, Reichweite), `test_town_network` (Sitzen auf Client, Snapshot mid-sit).

### B9 Lichtpfosten anzünden und pflegen
**Design:** Ein Lichtpfosten hat drei Zustände:
1. **Kalt** (frisch gebaut): Laterne dunkel, Pfosten trägt nur die **Baureichweite**. E („ANZÜNDEN", kostet 1 Glimmkappe aus Rucksack/Lager) entzündet die Flamme mit Funken-Animation.
2. **Brennt:** nachts brennt er, am Tag ist die Laterne gedimmt und sparsam. Vorrat `f` (0..1000) sinkt **nur nachts** (Standard: 3 Nächte pro Füllung, `fuel_nights` in `town.json`).
3. **Leer:** nur Glut (kleines Licht), kein Schutz. E („NACHFÜLLEN", 1 Glimmkappe = +500) füllt auf; Prompt auch bei < 60 %.
- **Folgen:** `lit_circles()` / `light_depth()` / `spawn_blocked` zählen nur brennende Pfosten (Hütte und andere Quellen unverändert). Baureichweite bleibt unabhängig. Neue Meldung `lamp_out` (Banner „EIN LICHT ERLISCHT" nachts) und kleines Symbol auf der Karte (C19).
- **Host/Netz:** `u.f` und `u.l` auf dem Host; Brennen wird in Schritten von 5 % über `_rpc_lamp(id, f, l)` verteilt, Beitritt per Snapshot; Anzeige zwischen Meldungen berechnet jeder Peer aus Uhr. Wirtschaft: Lager darf als Vorrat dienen (Kosten zuerst Lager, dann Rucksack, wie beim Bauen).
- **Bestehende Städte:** fehlendes `u` = brennend, voll (Abschnitt 2). Das Dev-Menü „FERTIGE STADT" füllt alle Lampen.
- **Haken für später:** Siedler (Valdric) füllt Lampen nach, Öl statt Kappen, mehr Lichtquellen.
- **Kunst:** Laternenzustände (dunkel, Glut, brennt) in `art_lamp.py` (Glow-Streifen kann bleiben, Basis-Laterne wird getauscht).
- **Test:** `test_night` (Spawn-Sperre folgt Lampen), `test_town` (Anzünden, Verbrauch über Nächte, Nachfüllen, Save/Load, Client), `test_town_network`.

### B13 Klappen an Lager und Werkstatt
**Realität:** Lager und Werkstatt sind offene Stände ohne Tür; nur die Hütte hat eine. Passend ist die **Marktstand-Klappe**: ein Brett unter dem Dachrand, das nachts herunterklappt (Stand ist zu) und tagsüber als Vordach hochsteht.
- **Zustände:** `geschlossen → halb → offen` (5 Frames, 0,6 s). Regeln: tags offen; nachts (`night_amount > 0,5`) zu, **außer** jemand steht in der Türzone (`front`) oder ein Siedler arbeitet dort. Kein Blockieren: nachts öffnet **E** am Lager die Klappe (Kurz-Animation) und danach das Lagerfenster; sie schließt sich 20 s nach dem Weggehen. Rein optisch, ändert keine Kollision.
- **Werkstatt:** die Klappe verdeckt nur den überdachten Teil (Werkbank); Schmiede und Amboss stehen weiter offen, die Glut bleibt sichtbar.
- **Fuchs:** schnüffelt nachts an der geschlossenen Klappe (Sniff-Anim bleibt, Ziel-Punkt unverändert).
- **Ton:** leises Quietschen und Schlag (`tools/audio_hut.py`-Stil), positional.
- **Hütte:** vorhandene `Doorway`-Animation bleibt; optional geht die Tür einen Spalt auf, wenn ein Siedler hinein-/herausgeht (Haken, kein Muss).
- **Kunst:** je Gebäude ein Frame-Streifen (`<piece>_shutter.png`, 5 Frames) als gerenderter Teil um eine Drehkante (`art_town.part()` pro Winkel). Teil liegt über dem Basisbild; `window` für den Aufbau.
- **Test:** Vorschau `--night --shutter`; Check: Zustand folgt Uhr/Anwesenheit, E nachts öffnet Fenster.

## 5. C – Immersion

### C15 Abendfeuer als Ritual
**Idee:** Abends ist das Feuer im Hof der Treffpunkt; die Spielerin soll das spüren und belohnt werden.
- **Feuerrunde** (`FireCircle`, reine Funktionen + kleiner Host-Zustand): in `evening_window()` setzen sich Siedler auf freie Plätze (Stumpf, Baumstamm, Bänke in Reichweite des Feuers, B8). Plätze werden nach **Reihenfolge der Anwesenden** vergeben, Rest steht. Hat `Settler` einen `sit`-Clip, sitzt er (Valdric hat ihn).
- **Wohlfühlbonus:** sitzt die Spielerin am Feuer und mindestens ein Siedler ist in der Runde, erhält sie nach 8 s **Feuerwärme**: `HealthComponent.regen` 6 HP über 6 s, danach 90 s Abklingzeit; zusätzlich kurz warmes Aufglimmen am Feuer und im Gesicht (leichte Lichtpuls-Optik, kein Bildschirm-Effekt). Keine neue Buff-Infrastruktur (die Regeneration gibt es).
- **Geschichten:** nach der ersten Minute der Runde erzählt ein Siedler eine **Feuergeschichte** (siehe C16, Thema `fire_story`), mit Tageszähler, damit nichts doppelt kommt.
- **Rand:** nicht in der Nacht des Raids (Warnung bricht die Runde ab), nicht bei Dialog/Story (`story_lock`).
- **Haken für später:** Feste (Vollmond-Feuer), Musik, Essen teilen mit dem Kochsystem.
- **Test:** `test_town` (Platzvergabe, Bonus einmal je Abklingzeit, Abbruch bei Raid).

### C16 Siedler reagieren aufeinander und auf die Stadt
**Idee:** Die Stadt redet. Zwei Arten: **Gespräche** (zwei Siedler) und **Reaktionen** (eine Zeile auf ein Ereignis).
- **Daten:** neu `data/chatter.json`: Themen `{id, kind: "meet" | "event" | "fire_story", who: [a, b], when {spot, window, night, level, flag}, lines [[sprecher, text], ...], cooldown}`. **Alle Texte sind Platzhalter** für den Dialog-Writer (`docs/prompts/dialogue_writer.md`).
- **Auswahl deterministisch:** `SettlerChatter` wählt Thema aus (Tag, Zeitfenster, Spot, Gewichte) per Hash, damit jeder Peer dasselbe sieht, **ohne Netzverkehr**. Zeilen erscheinen nacheinander im Abstand von 3–5 s.
- **Ereignisse** (aus Abschnitt 2): `built(lamp_post)` („Endlich Licht am Weg."), `built(piece)`, `level_up`, `resident_joined`, `raid_warning`, `night_survived`, `lamp_out`. Der nächste Siedler im Umkreis antwortet; je Ereignis höchstens einmal.
- **Anzeige:** neue `SettlerBubble` (kleine Blase im Rankenstil über dem Kopf, 160 px Sichtradius, wie die Sprechblase im `BoardWindow`) statt `SpeechBox`, die der Geschichte und dem direkten Ansprechen vorbehalten bleibt. Blase blendet mit Spielerabstand ein/aus; keine Eingabe, nichts pausiert.
- **Treffpunkte:** Spots `fire`, `bench`, `bannerpost` (Standarte, A2) zählen für `meet`, wenn zwei Siedler dort stehen.
- **Vertrauen:** manche Zeilen setzen Mindestvertrauen voraus (`talk`-Schwelle wie bei Gustav).
- **Haken für später:** Siedler-Gerüchte aus Welt-Flags, Gespräche mit der Spielerin als Option.
- **Test:** `test_town_story` (Auswahl stabil, Cooldowns, Ereignisse lösen aus, keine Zeile doppelt in Folge).

### C19 Stadt als Ort auf der Karte
- **Marker:** `MapWindow` zeichnet bei entdeckter Stadt eine **Flagge** (im Bannerdesign) an der Hütte, den **Stadtnamen** und den **Lichtkreis** als gestrichelten Rand der brennenden Quellen (`lit_circles`); Baureichweite als blasse zweite Linie.
- **Gebäude-Symbole:** 5×5-Pixelsymbole je Rolle (Lager, Werkstatt, Lampe, Bank) aus `data/map_markers.json`, abhängig vom Zoom (ab 0,42 wie Symbole). Leere Lampen blass. Siedler-Marker gibt es bereits (`quest_actors`).
- **Betreten:** lokale Erkennung mit Hysterese: beim ersten Betreten des Lichtkreises je Tag zeigt `TownBanner` den **Stadtnamen** mit Untertitel (Stufe, Tag); beim Verlassen kurz leiser „VERLASSE GLIMMRAST" (abschaltbar in Einstellungen, `GameSettings`).
- **Discovery:** nur Zellen, die `MapDiscovery` kennt; Stadtkarte aber immer sichtbar, sobald sie gegründet ist (sie ist die eigene).
- **Test:** `test_map_presence` erweitern; Capture der Karte mit Stadt.

### C20 Nachtschutz sichtbar
**Idee:** Das Licht schützt – das soll man sehen, hören und beobachten können.
1. **Lichtrand:** in `night_fog.gdshader` (nutzt bereits bis zu 8 Lichtkreise) ein **dünnes, gedithertes Randband**: warmes Teal an der Grenze des brennenden Lichts, schwächer an Lücken; Stärke mit Nacht und Nebel. Nur brennende Quellen (B9).
2. **Funken beim Zurückdrängen:** wenn `NightBehavior.limit` ein Wesen am Rand abbremst oder hinausschiebt, meldet es `TownManager.light_touch(pos, stärke)` (Host); Funken-Burst an dieser Stelle für alle Peers (`_rpc_light_touch`, gebündelt, Rate-Limit 4/s). Kein Schaden, rein Rückmeldung.
3. **Valdric hält den Rand:** bei `raid_warning` wechselt Valdric aus seinem Tagesplan in **Wache am Rand**: er geht zum Punkt am Lichtrand in Richtung der Sammelstelle der Wesen (`TownManager.alert {on, angle}`, klein, vom Host gesendet), steht mit gezogener Waffe (Idle mit Schwert), bis `raid_end`, dann zurück in den Plan. Wesen im Umkreis von 48 px um ihn **weichen aus** (kleine Anpassung in `NightBehavior`, nur Host). Kein neuer Kampf.
4. **Ton:** leises, tiefes Summen am Lichtrand bei Warnung, Funkenknistern beim Zurückdrängen.
- **Hängt an:** B9 (brennende Lampen), A7 (kein Einfluss), C16 (`raid_warning`-Zeilen).
- **Risiken:** Gegner-Hooks sind sparsam zu halten (nur `limit` ergänzt um Meldung); Valdrics Dynamik bricht die „reine Funktion" für Zeiten des Alarms, daher der kleine `alert`-Zustand mit Snapshot.
- **Test:** `test_night` (Meldung bei Abbremsen, Valdric am Rand, Rückkehr), Vorschau `--night --raid`.

## 6. Reihenfolge

| Phase | Inhalt | Warum zuerst |
|---|---|---|
| 0 | Struktur-Zustand `u`, Stadt-Ereignisse, `SeatSpot` | tragen mehrere Features |
| 1 | A7 Nachtlichter, A2 Standarte/Hütten-Banner, A6 Alter und Pflege | reine Optik und Daten, geringes Risiko, sofort sichtbar |
| 2 | B8 Bank, B13 Klappen | kleine Interaktionen ohne Netz-Neuland |
| 3 | B9 Lichtpfosten-Zustände | berührt Nachtregeln und Netz; Grundlage für C19/C20 |
| 4 | C19 Karte und Betreten | nutzt B9 und A2 |
| 5 | C15 Feuerrunde, C16 Gespräche | nutzen B8, Ereignisse und Spots |
| 6 | C20 Nachtschutz | braucht B9, C16, Gegner-Hook |
| 7 | A5 Festgetretener Boden | größte Technik (Shader-Global), zuletzt und isoliert |

Jede Phase endet mit grünen Tests, Vorschau-Captures (`preview_town.tscn`) und einem Absatz in `docs/town.md`.

## 7. Dateien (Überblick)

- Neu: `src/town/town_wear.gd`, `src/town/settler_chatter.gd`, `src/town/settler_bubble.gd`, `src/town/fire_circle.gd`, `src/entities/props/seat_spot.gd`, `data/chatter.json`, `tools/test_town_decor.tscn`, `tools/test_town_wear.tscn`, `tools/test_town_chatter.tscn`.
- Erweitert: `town_manager.gd` (u, Ereignisse, `alert`, `light_touch`, Snapshot), `town_structure.gd` (Seats, Klappen, Pflege-Overlays, Lampenzustand), `town_rules.gd`, `settler.gd` (Bank, Alarm, Feuer), `hut.gd` (Banner je Stufe), `map_window.gd`, `town_banner.gd`, `night_behavior.gd`, `night_fog.gdshader`, `ground_tone.gdshader`, `meadow_details.gd`, `data/town.json`, `data/settlers.json`, `data/map_markers.json`.
- Kunst: `tools/art_town.py` (Standarte, Laternen, Klappen, Overlays), `art_lamp.py` (Laternenzustände), `art_hut_fresh.py` und `hut_outside.py` (Banner, Efeu), `tools/audio_town.py` (neu, Quietschen, Funken, Summen).

## 8. Offene Entscheidungen (bei Umsetzung kurz klären)

1. Bank: Blickrichtung des Sitzenden (Modell prüfen) und Stärke der Erholung.
2. Lichtpfosten: Brenndauer (3 Nächte/Füllung?) und ob die Hütte selbst eine Lampe braucht.
3. Feuerwärme: 6 HP/6 s alle 90 s – Wert für das Spiel passend?
4. Valdric am Rand: soll er Gegner wirklich zurückdrängen oder nur Präsenz zeigen?
5. Stadtname beim Betreten: einmal je Tag oder bei jedem Betreten?

## 9. Später (aus der Ideenliste, bewusst nicht jetzt)

A1 Deko-Kategorie (Fässer, Kisten, Wäscheleine, Kübel, Wegweiser), A3 Wappen und Stadtfarbe, A4 Zaun-Varianten/Tor, B11 Brunnen/Kochstelle/Ofen, B12 Briefkasten/Glocke, C17 Festtage, C18 Stadttiere, C14 Stadtgeräusche (nur die Töne dieser Features kommen mit), D21 weitere Siedler, D22 Stufenbelohnungen, D23 Wohnhäuser, D24 Felder, D25 Verteidigungsbauten, D26 Karawane, D27 Rollen für Mitspieler, D28 Chronik.
