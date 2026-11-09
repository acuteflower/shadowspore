# Level & Fortschritt – Konzept „Die Wachstumsranke"

> **GEBAUT (2026-11-09) – diese Entscheidungen ersetzen die Vorschläge weiter unten:**
> - Keine Rüstung pro Stufe. Rüstung ist ein neuer Wert (`HealthComponent.armor`, Schaden × 80/(80+Rüstung)), kommt nur an Meilensteinen (+1/+2) und später hauptsächlich aus Ausrüstung.
> - Jede Stufe: +3 Leben, +2 Ausdauer. Meilensteine alle 5 Stufen (5/10/15/20/25/30: ERSTE WURZEL, ZWEITER ATEM, DÄMMERWACHE, FESTER STAND, SCHATTENKUNDIG, VOLLENDUNG) mit Talismanplatz und etwas mehr Überheilung. Alles in `data/level_rewards.json`, rein gerechnet in `LevelRewards`.
> - Neue XP-Kurve `base 22 · n^1.45` (`data/levels.json`, Stufe 30 = Obergrenze, ~34 000 XP gesamt). XP skaliert bereits mit der Gegnerstärke. Das Level macht die Nächte weiter schwerer (`NightRules`).
> - **Belohnungen sind nicht automatisch:** Der Charakter zählt nach der *eingesammelten* Stufe (`ProgressComponent.claimed`, Host-Wahrheit, gespeichert), nicht nach der erreichten. Einsammeln = im Fenster halten (Globus oder Knospe unten rechts, ~0,75 s).
> - Fenster `ProgressWindow` (`src/ui/progress_window.gd`, Taste P, Klick auf das Stufenabzeichen der Hotbar, Pausemenü → FORTSCHRITT): Ranke von links nach rechts, Globen pro Stufe, Karten mit den Belohnungen darunter, Zukunft im Schleier (`progress_veil.gdshader`; Meilensteine schimmern durch, ferne Zahlen und Namen sind verdeckt), Pan/Zoom wie die Karte (unter Zoom 0,9 werden Karten zu Punkten). Töne: `tools/audio_progress.py`.
> - Weggelassen für jetzt: Rezeptstufen und Titel. Dev: ENTWICKLER → +100 XP / +1 STUFE. Test: `tools/test_levels.tscn`.
>
> Status der ursprünglichen Fassung: **Konzept** (Stand 2026-11-09). Ziel: Das Level bekommt Gewicht. Jede Stufe belohnt sichtbar (Leben, Rüstung, Ausdauer, Fähigkeitspunkt, ab und zu eine echte Freischaltung), und ein neues Vollbild-Fenster **FORTSCHRITT** zeigt den Weg: links die erreichten Stufen mit ihren Belohnungen, rechts die Zukunft im Schleier. Reihenfolge laut Wunsch: **erst das Fenster, danach die echten Belohnungen** – das Konzept hält beides zusammen, damit das Fenster nicht neu gebaut werden muss.

---

## 1. Ist-Zustand (aus dem Code gelesen)

| Was | Stand |
|---|---|
| Kurve | `Levels` (`src/systems/levels.gd`, `data/levels.json`): XP von Stufe n nach n+1 = `30 · n^1.7`, auf 5 gerundet. Max-Stufe 30. Nichts außer der Gesamt-XP wird gespeichert, das Level wird abgeleitet. |
| Quellen | **Nur** Kills (`DropComponent`: Spinne 12, Lauscher 12, Brecher 22, Ambush-Spinne 150), Nacht überlebt (`night.survive`: 8 + 1,5 · Stufe) und Minentruhen (6). Keine Quest-, Bau-, Entdeckungs-, Angel- oder Koch-XP. |
| Belohnung | **Keine.** Das Level steht im HUD (Hotbar-Ranke: goldenes Licht bis zur Knospe, „LV n", Aufstiegs-Welle) und im Fähigkeitsfenster als „`Level − 1` PUNKTE / FÜR SPÄTER" (nie ausgegeben). |
| Spielerwerte | 100 HP fest (`HealthComponent.max_health`), 100 Ausdauer fest (`StaminaComponent`). **Es gibt keinen Verteidigungswert**: `take_damage` zieht den Schaden 1:1 ab. Ausrüstung hat Slots (Waffe, Kopf, Brust, Beine, Füße, 3 Talismane), aber keine Rüstungs-Items. |
| **Gegenseite** | Das Level macht das Spiel aktuell nur **schwerer**: `NightRules` rechnet das Nacht-Budget mit +10 % je Stufe des Stärksten, die Gegner-Lebenspunkte mit +6 % je Stufe (Schaden +60 % davon). Kommentar im Code: „a player always has 100 HP". |
| Mehrspieler | `ProgressComponent` hält XP/Kupfer auf dem Host und schickt sie **nur an den Besitzer**. Andere Peers kennen weder Level noch Stufenwerte. |

### Rechnung zur jetzigen Kurve

Gemessen an einer Simulation (Nacht-Budget, 70 % Kills, nur Kill- + Überlebens-XP):

- Stufe 5 nach ca. 10 Nächten, Stufe 10 nach ca. 41, Stufe 15 nach ca. 97, Stufe 20 nach ca. 177, Stufe 25 nach ca. 282 Nächten (eine Nacht = ein Tag = 12 Minuten). **Stufe 30 ist praktisch unerreichbar.**
- Früh geht es fix (Stufe 2 und 3 in den ersten beiden Nächten), spät zäh. Die Gegner wachsen mit dem Level, ihre XP aber nicht – das Level läuft der Belohnung davon.

**Fazit:** Kurve flacher, Gegner-XP mitwachsen lassen, neue Quellen, und die Stufe muss dafür etwas geben.

---

## 2. Leitplanken

1. **Host-autoritativ, Level bleibt abgeleitet.** Alle Stufenwerte sind eine reine Funktion `Level → Werte` (`LevelRewards`), nichts Neues im Spielstand außer einem kleinen Log (siehe 7.4). Alte Spielstände funktionieren ohne Migration (die Stufe wird aus der XP neu abgeleitet).
2. **Daten in JSON.** Kurve, Werte je Stufe und Meilensteine liegen in `data/levels.json` (Kurve + Stats) und `data/level_rewards.json` (Meilensteine, Texte, Icons). Die UI liest nur.
3. **Der Schwierigkeitsgrad ist überall gleich, er steigt mit der Nacht** (Projektregel). Stufen sperren deshalb **keine Gebiete**. Belohnungen sind Kraft, Komfort und Freischaltungen von Systemen – keine Mauern.
4. **Level = Komfort, Ausrüstung/Fähigkeiten/Stadt = die scharfen Werkzeuge.** Die Stufenboni sollen das Mitwachsen der Gegner knapp übertreffen (siehe 4.3), nicht ein Rüstungsrennen auslösen.
5. **Nichts, was nicht besprochen ist, wird gebaut.** Alles in Abschnitt 5 (Meilensteine) ist **Vorschlag**; gebaut wird erst, was du abnickst.
6. Eigene Bilder: nur wo nötig (das Fenster zeichnet fast alles prozedural im Vinen-Stil); Kunst-Aufträge laufen über den `gpt-6.1-terra`-Subagenten.

---

## 3. Das Fenster: FORTSCHRITT

### 3.1 Wie man es öffnet

- Neue Aktion `progress`, Vorschlag **P** (frei; M Karte, F Fähigkeiten, I/Tab Inventar, B Bauen, L Freikamera sind belegt). Controller: Schultertaste-Kombi oder Auswahl im Menü, später.
- Klick auf das **„LV n"-Abzeichen der Hotbar-Ranke** öffnet es (kleiner Cursor-Hinweis `click`).
- Pausemenü: Schaltfläche (wie beim Fähigkeitsgraphen) – das gesperrte KARTE-Tag bleibt für die Karte reserviert.
- Gesperrt in Storysequenzen, beim Tod, in Intro/Hütte bis `hud_unlocked`, wie F. `InputManager.progress_open` (analog `skills_open`) hält Bewegung, Schläge, Interaktion an.
- Bei Wechsel Karte ⇄ Fähigkeiten ⇄ Fortschritt schließt sich das eine, das andere öffnet sich (kein Stapeln).

### 3.2 Öffnen & Schleier

Dasselbe Erlebnis wie Karte und Fähigkeiten: der Schattenschleier (`assets/shaders/map_veil.gdshaderinc`: Palette, FBM, Dithering, Nebel, ausgefranste Aufdeckkante, Öffnungswelle) füllt den ganzen Schirm und **zieht sich von Ellie aus zurück**. Neues Shader-Pärchen `progress_veil.gdshader` nutzt dieselbe Include. Hintergrund in aufgedeckten Bereichen: dunkle Leere, feine Sterne, Punktgitter – hier aber **Wurzelfäden und Jahresring-Andeutungen** statt Sternen im unteren Drittel (Erde, aus der die Ranke wächst).

### 3.3 Aufbau (Skizze, 640 × 360)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ╭─ WACHSTUM ─────╮                                      ╭─ PUNKTE: 7 ─╮ [F] │
│ │ STUFE 8        │                                      ╰─────────────╯     │
│ │ LEBEN     129  │   Die Ranke ───────────────────────────────────────────   │
│ │ RÜSTUNG     7  │   ◉────◉────◉────◉────◉────◉────◉────◉────◍ ~ ~ ◌ ~ ~ ◌   │
│ │ AUSDAUER  114  │   1    2    3    4   [5]   6    7   ▶8     9  10 11 12   │
│ │ NÄCHSTE: +3 L  │   ╎    ╎    ╎    ╎    ╎    ╎    ╎    ╎     ╎            │
│ ╰────────────────╯  ┌╌┐  ┌╌┐  ┌╌┐  ┌╌┐ ┌─────┐┌╌┐  ┌╌┐  ┌╌┐   ░░░░         │
│                      ♥3   ♥3   ♥3   ♥3 │ERSTE││♥3   ♥3   ♥3    ░░?░░         │
│  XP-HERKUNFT         ◈1   ◈1   ◈1   ◈1 │BLÜTE ││◈1   ◈1   ◈1    ░░░░         │
│  (Jahresringe)       ✦1   ✦1   ✦1   ✦1 │Tali- ││✦1   ✦1   ✦1                 │
│                      └╌┘  └╌┘  └╌┘  └╌┘ │sman I││└╌┘  └╌┘  └╌┘                │
│                                         └──────┘                              │
│  ◂ Ziehen · Rad: Zoom · R: zu mir · Leer: fliegen · Q E: Zoom       [Zoom]   │
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Die Ranke** läuft waagerecht von links (Stufe 1) nach rechts. Pro Stufe eine Knospe/Blüte, Abstand ca. 64 px bei Zoom 1. Meilenstein-Stufen (5, 10, 15 …) sind größere Blüten mit mehr Blütenblättern.
- **Erreicht:** offene Blüte in Gold/Türkis, Ranke leuchtet bis zur aktuellen Stufe (dieselbe goldene Lichtlinie wie die XP-Ranke der Hotbar, hier durchgehend).
- **Aktuelle Stufe:** Knospe, die sich mit dem XP-Fortschritt füllt (gleiches Licht wie `Hotbar._update_xp`), atmender Halo, Wegweiser „▶". Fortschrittszahl „212 / 450 XP" auf einer Rindenpapier-Karte darüber.
- **Zukunft:** die Ranke läuft weiter, aber **im Schleier**: nächste ~3 Stufen dunkel und klar lesbar, danach nimmt der Schleier zu (Nebel dichter, Zahlen verschwimmen, Belohnungs-Silhouetten bleiben). Meilensteine schimmern durch den Nebel, ihr Name wird erst aus der Nähe (≤ 3 Stufen) lesbar, ihr Inhalt erst, wenn sie die nächste Stufe sind. Nachts öffnen sich im Nebel Paare magenta Augen (Schleier-Mood, wie die Karte).
- **Belohnungen** hängen unter jeder Stufe an Fäden wie die Ausrüstung im Inventar (Windspiel-Look): kleine Blatt-Karten (`VineStyle.paper`) mit Glyphe + Wert. Stufenwerte sind kleine Blätter, ein Meilenstein ist eine **große** Karte mit Icon, Namen, Text. Bei erreichten Stufen: Haken-Knospe; bei kommenden: ausgegraut.
- **Linke Karte „WACHSTUM":** deine Gesamtwerte jetzt (Leben, Rüstung + Prozent, Ausdauer, Punkte) und „NÄCHSTE STUFE: +3 LEBEN …". Hängt wie die Karten im Fähigkeitsfenster frei an einem Vinenast, ohne Kasten.
- **Unten links „HERKUNFT":** ein Baumstumpf-Querschnitt, dessen **Jahresringe** zeigen, woher die XP kamen (Nächte / Geschichte / Entdecken / Stadt / Boss) – Ringbreite = Anteil. Hover nennt Zahlen. (Nettes Extra, Phase 7.)
- **Auswahl:** Klick/Pfeiltasten wählen eine Stufe, die Karte darunter vergrößert sich; Doppelklick zoomt hinein; Leertaste fliegt zur aktuellen Stufe, R zeigt alles.

### 3.4 Pan & Zoom (wie die Karte)

- Rad zoomt zum Mauszeiger, Q/E und Schultertasten zur Mitte, die Zoom-Ranke am rechten Rand ist ziehbar.
- Ziehen mit LMT/MMT oder WASD/linker Stick mit Trägheit. Anders als die Karte ist das Ziehen **hauptsächlich waagerecht** (die Ranke ist eine Zeitleiste); senkrecht nur wenige Pixel Spielraum für große Karten.
- Zoomstufen: weit (nur Knospen und Meilenstein-Silhouetten), normal (Stufenwerte), nah (Meilenstein-Karte mit Beschreibung und Chronik).
- Start: zentriert auf der aktuellen Stufe, mit leichtem Flug von links nach dort („du wächst bis hierher").

**Technik:** Die Pan/Zoom-Logik steckt heute doppelt in `MapWindow` (1173 Zeilen) und `SkillTreeWindow` (845). Statt einer dritten Kopie wird sie als kleiner Helfer `PanZoomView` herausgezogen (Offset, Zoom, Trägheit, Rad-zum-Zeiger, Zoom-Ranke, Grenzen); die beiden alten Fenster bleiben **unverändert** (kein Refactor-Risiko).

### 3.5 Aufstieg im Fenster und in der Welt

- Neue Stufe in der Welt: goldene Ringe aus ihren Füßen (wie beim Essen), Blütenblätter, kurzer Ton, die Hotbar-Welle bleibt; ein Banner-Streifen „STUFE 7 · +3 LEBEN · +1 RÜSTUNG" (Vorbild `TownBanner`). Meilenstein: größere Variante mit Siegel-Aufleuchten.
- Das LV-Abzeichen bekommt eine **„NEU"-Knospe**, bis das Fenster geöffnet wurde. Beim Öffnen fliegt die Kamera zur neuen Stufe, die neue Blüte **öffnet sich vor deinen Augen** (Reveal-Animation wie beim Erkunden im Graph), Werte zählen hoch.
- Belohnungen werden **automatisch** gewährt. Das Fenster ist die Zeremonie, kein Abholen (Alternative: „Halten zum Annehmen" nur für Meilensteine – siehe Fragen).

---

## 4. Die Werte: Kurve und Stufenboni

### 4.1 XP-Kurve (Vorschlag)

`xp_to_next(n) = 22 · n^1,45`, auf 5 gerundet (statt `30 · n^1,7`). Max-Stufe bleibt 30, **Gesamt bis 30: 35.835 XP** (vorher ca. 103.000).

Simulation (gleiches Modell, aber Gegner-XP × Stärke und +40 % aus neuen Quellen): Stufe 5 in Nacht 5, Stufe 10 in Nacht 14, Stufe 15 in Nacht 25, Stufe 20 in Nacht 37, Stufe 25 in Nacht 49, **Stufe 30 in Nacht 62** (≈ 12 Spielstunden pur durch Nächte; mit Erkunden/Bauen/Bossen realistisch länger). Die Zahlen sind ein Startpunkt: ein Test-Bot (siehe 9) prüft sie bei jeder Änderung, `base`/`exponent` stehen in der JSON.

Schutz gegen „zu schnell": die ersten Stufen bleiben bewusst flott (Stufe 2 ≈ 2 Spinnen, Stufe 3 nach der ersten Nacht), danach steigt der Preis stetig.

### 4.2 Stufenwerte (Vorschlag)

| Wert | Formel | Stufe 30 |
|---|---|---|
| **Leben** | 100 + 3 pro Stufe + 8 pro Meilenstein (5, 10, … 30) | 235 |
| **Rüstung** (neu) | +1 pro Stufe ab 2 | 29 → −27 % Schaden |
| **Ausdauer** | 100 + 2 pro Stufe | 158 |
| **Fähigkeitspunkt** | +1 pro Stufe ab 2 (wie schon angezeigt: `Level − 1`) | 29 |

**Rüstung** wirkt als abnehmender Ertrag: `Schaden · 80 / (80 + Rüstung)`, Obergrenze 70 % Minderung. Die Anzeige nennt immer beides: „RÜSTUNG 29 (−27 % SCHADEN)". Ausrüstung kann später Rüstung dazugeben (die Slots existieren schon). Dauerschaden (Brand, `take_tick`), Story-Treffer (`take_survivable`) und `kill` ignorieren Rüstung. Sie greift nur in `HealthComponent.take_damage` (Host).

### 4.3 Gleichgewicht mit der Nacht

Aktuell wächst die Gegner-Seite so (`NightRules`): Lebenspunkte `1 + 0,06 (L−1)`, Schaden `1 + 0,6 · 0,06 (L−1)`. Auf Stufe 30: Gegner-Leben ×2,74, Gegner-Schaden ×2,04.

Der Spieler gewinnt auf Stufe 30: Leben ×2,35 und −27 % Schaden. Die **Überlebensfähigkeit** pro Gegnerschlag steigt also um den Faktor `2,35 / (2,04 · 0,73) ≈ 1,6` gegenüber Stufe 1. Das gleicht die Stufen aus und lässt eine Reserve für Fehler, aber den eigentlichen Machtsprung müssen Waffe, Fähigkeiten und Stadt liefern. Leitregel: **auf jeder Stufe soll sich ein Treffer ungefähr gleich gefährlich anfühlen, nur ohne Ausrüstung kippt es spürbar**. Der Test-Bot rechnet „Treffer bis Tod" für Spinne, Lauscher und Brecher je Stufe, damit niemand versehentlich Gott oder Glas wird.

Der Code-Kommentar „a player always has 100 HP" in `NightRules.damage_scale` wird entsprechend geändert.

### 4.4 Gesamttabelle (Vorschlag)

| Stufe | XP bis nächste | XP gesamt (bei Beginn) | Leben | Rüstung | −Schaden | Ausdauer |
|---|---|---|---|---|---|---|
| 1 | 20 | 0 | 100 | 0 | 0 % | 100 |
| 2 | 60 | 20 | 103 | 1 | 1 % | 102 |
| 3 | 110 | 80 | 106 | 2 | 2 % | 104 |
| 4 | 165 | 190 | 109 | 3 | 4 % | 106 |
| **5** | 225 | 355 | **120** | 4 | 5 % | 108 |
| 6 | 295 | 580 | 123 | 5 | 6 % | 110 |
| 7 | 370 | 875 | 126 | 6 | 7 % | 112 |
| 8 | 450 | 1.245 | 129 | 7 | 8 % | 114 |
| 9 | 530 | 1.695 | 132 | 8 | 9 % | 116 |
| **10** | 620 | 2.225 | **143** | 9 | 10 % | 118 |
| 12 | 810 | 3.555 | 149 | 11 | 12 % | 122 |
| **15** | 1.115 | 6.280 | **166** | 14 | 15 % | 128 |
| **20** | 1.695 | 12.990 | **189** | 19 | 19 % | 138 |
| **25** | 2.340 | 22.730 | **212** | 24 | 23 % | 148 |
| 29 | 2.905 | 32.930 | 224 | 28 | 26 % | 156 |
| **30** | – | 35.835 | **235** | 29 | 27 % | 158 |

(Fett = Meilenstein-Stufen. Die vollständige Tabelle erzeugt `LevelRewards`; hier stehen nur die lesbaren Zeilen.)

### 4.5 Was beim Aufstieg passiert

- Das neue Maximum **hebt auch das aktuelle Leben um denselben Betrag** (kein Nachteil durch den Aufstieg, die gewonnenen Punkte sind sofort da). Ob zusätzlich ein kleiner Atemzug-Heiler läuft (z. B. regen 10 über 5 s), ist offen (Fragen).
- Der Aufstieg mitten im Kampf ist ein kurzer Lichtimpuls, kein Spielstopp. Das Fenster öffnet sich **nie von selbst**.

---

## 5. Meilensteine (Vorschläge – nichts davon ist beschlossen)

Nicht jede Stufe soll sich gleich anfühlen. Alle fünf Stufen (und ein paar Zwischenstufen) gibt es eine echte Freischaltung. Sie hängen an **bestehenden oder schon besprochenen Systemen**, damit sie nicht in die Luft gebaut sind:

| Stufe | Name (Platzhalter) | Inhalt | Hängt an |
|---|---|---|---|
| 2 | Erster Trieb | Fähigkeitspunkte werden echt: der Zähler im F-Fenster bekommt Bedeutung | Skill-Graph (`SkillTreeComponent`) |
| 5 | Erste Blüte | **Talisman-Platz I**, Titel „WANDERIN" | Slot `talisman_1` existiert |
| 8 | Tiefer Atem | Ausdauer erholt sich 10 % schneller | `StaminaComponent.regen_per_sec` |
| 10 | Wurzeltiefe | Überheilung 10 → 15 % | `HealthComponent.overheal_ratio` |
| 12 | Zweite Blüte | **Talisman-Platz II** | Slot `talisman_2` |
| 15 | Handwerkerschaft | Rezept-Stufe II bei Gustav und in der Küche (bessere Werkzeuge, mehr Gerichte) | `data/recipes.json` mit `level`, Gustav-Werkbank, `data/cooking.json` |
| 20 | Dritte Blüte | **Talisman-Platz III**, Titel | Slot `talisman_3` |
| 25 | Nachtgeübt | Überheilung 15 → 20 %; Hotbar-Ranke blüht voll aus | Overheal, `Hotbar` |
| 30 | Vollendung | Titel „DIE LICHTBRINGERIN", Cursor-Akzent „Schleierblüte", Ellies Mantelsaum schimmert violett (Kunst) | `CursorArt`, Charakter-Kunst später |

Weitere Kandidaten für Zwischenstufen (Ideenliste, alle optional):

- **Angel/Koch/Mine mitwachsen:** „Angelfeinheit" (kleiner Bonus beim Biss-Timing), „Frische Würze" (Gerichte halten länger), „Spitzhackenschlag" (Stein bricht einen Treffer früher). Jeweils klein und ein eigenes Gespräch wert.
- **Wegstein-Gunst:** Wegsteine kosten bei höherer Stufe weniger Haltezeit.
- **Lastenträger:** +Taschenplätze (wenn das Inventar je erweitert werden soll).
- **Titel** unter dem Namen im Fenster (reine Freude, null Spielwirkung).
- **Kosmetik ohne Balance:** HUD-Ranken bekommen Blüten ab Stufe 5/10/…, die Schlüssel-Steine (`key_cap`) bekommen Moos, der Cursor eine Akzentfarbe.

Regel für jeden Meilenstein: **ein Satz, ein Icon, eine einzige klare Wirkung**, und er ist testbar (wie eine Zeile in `LevelRewards`).

---

## 6. Neue XP-Quellen (damit die Kurve lebt)

Damit die gesenkte Kurve nicht nur „mehr vom Gleichen" ist, kommen XP aus allem, was Spaß macht. Beträge sind Vorschläge relativ zur neuen Kurve (Stufe 5 braucht 225 XP, Stufe 10 braucht 620):

| Quelle | XP (Vorschlag) | Umsetzung |
|---|---|---|
| Kampf: Gegner | Basis-XP × **Gegner-Stärke** (`EnemyScaling.health_scale`), damit sie mit dem Level mitwachsen | `DropComponent` |
| Nacht überlebt | wie bisher 8 + 1,5 · Stufe, +25 % ohne Verlust der Gruppe | `NightDirector` |
| Quest-Schritt / Quest fertig | 10–25 / 40–200 | Block `reward: {xp}` in `data/quests.json`, `QuestComponent` |
| Boss: Mornath | 1.500 (mehr als eine Stufe, ein Ereignis) | Boss-Kill |
| **Entdeckungen (einmalig)** | Wegstein erwecken 60, neue Fischart 15, neues Gericht 20, neue Methode 10, Kartenanteil je Gebiet 5 % = 25 | Bücher (`FishBook`, `CookingBook`), `Waystones`, `MapDiscovery` – die speichern „erstes Mal" schon |
| Stadt | Teil fertig 10–30, neuer Siedler 50, Stadtstufe 100–300 | `TownManager` |
| Mine | Truhe 6 (bleibt), neue tiefste Ebene 40 | `MineManager` (`deepest`) |
| Bau/Handwerk, Angeln, Kochen | nur „erstes Mal"-XP, keine laufende (kein Grind) | s. o. |

**Anti-Grind:** laufende Aktivitäten (Fische fangen, Holz hacken) geben keine XP; nur „erstes Mal", Quests, Kämpfe der Nacht und Bosse. So gibt es nichts zu farmen.

Die Quellen sind **Daten**, nicht Code: `ProgressComponent.award(copper, xp, source)` bekommt ein `source`-Label (`"night"`, `"quest"`, `"discovery"`, `"town"`, `"boss"`, `"mine"`), das Level-Log und die Jahresringe speisen sich daraus.

---

## 7. Technik

### 7.1 Neue / geänderte Dateien

| Datei | Zweck |
|---|---|
| `data/levels.json` | Kurve (`base`, `exponent`, `step`), `stats` {`life_per_level`, `armor_per_level`, `stamina_per_level`, `milestone_life`, `milestone_every`, `points_per_level`} |
| `data/level_rewards.json` | Meilensteine `{level, id, title, text, icon, kind, value}` |
| `src/systems/levels.gd` | bleibt (Kurve), liest die neuen Felder |
| `src/systems/level_rewards.gd` | **neu, rein**: `stats_at(level)`, `delta(level)`, `milestones_between(a, b)`, `next_milestone(level)`, `preview(level)` |
| `src/components/progress_component.gd` | `award(copper, xp, source)`, Signal `leveled(new_level, old_level)`, Level-Log |
| `src/components/health_component.gd` | `armor`, `set_stats(max, armor)` (RPC an alle Peers, Beitritts-Snapshot), `take_damage` rechnet Rüstung (Host), Anteil des neuen Lebens wird gutgeschrieben |
| `src/components/stamina_component.gd` | `set_max()` |
| `src/entities/player/player.gd` | hört auf `leveled`, wendet `LevelRewards.stats_at` an (Host), initial bei Spawn/Load |
| `src/ui/progress_window.gd` + `assets/shaders/progress_veil.gdshader` | das Fenster |
| `src/ui/pan_zoom_view.gd` | herausgezogener Helfer |
| `src/ui/hud.gd` / `hud.tscn` | `ProgressWindow` einhängen, `covered`-Liste, `Hud.PARTS`-Grow-in unbetroffen (Vollbild) |
| `src/autoload/input_manager.gd`, `project.godot` | Aktion `progress` (P), `progress_open` |
| `src/ui/hotbar.gd` | LV-Abzeichen klickbar, „NEU"-Knospe |
| `src/ui/progress_banner.gd` | Aufstiegs-Banner |
| `tools/audio_progress.py` | Öffnen, Aufstieg, Meilenstein, Aufdecken (synthetisiert, wie `audio_skills.py`) |

### 7.2 Mehrspieler

- Die Stufenwerte sind **eine Funktion der Stufe**; der Host kennt das Level jedes Spielers und sendet `HealthComponent._rpc_stats(max, armor)` an alle Peers (`call_local`, wie `_set_value`). Damit stimmen Lebensbalken, Mitspieler-Darstellung und Schadensrechnung überall. Auch `StaminaComponent` bekommt sein Maximum.
- Das **Level selbst** soll jeder Peer für jeden Spieler kennen (für Mitspieler-Marker im Fenster und kleine Namensschilder später): `ProgressComponent` sendet zusätzlich eine kleine, öffentliche Stufenzahl (`public_level`), die XP bleiben privat beim Besitzer.
- Belohnungen sind **pro Spieler**. Bei `award: "all"` (Beteiligung) bekommt jeder die XP.

### 7.3 Aufstieg bei vielen Stufen auf einmal

Ein Boss kann mehrere Stufen am Stück geben. Der Host sammelt sie in einem Aufstieg (`old → new`), wendet die Werte der neuen Stufe an, gewährt **alle** Meilensteine dazwischen, das Banner nennt die Summe, das Fenster zeigt alle Blüten nacheinander.

### 7.4 Speichern

`SaveGame` speichert wie bisher nur die XP. Neu im Spielerblock: `level_log` (Liste von `[tag, quelle]` je erreichter Stufe – für die Chronik) und `seen_level` (zuletzt im Fenster gesehene Stufe – für die „NEU"-Knospe). Alte Spielstände ohne Log zeigen im Fenster einfach keine Chronik für frühere Stufen.

### 7.5 Reihenfolge der Spiel-Systeme

- Beim Aufbau eines Spielstands darf das Stufenmaximum den **Wundstart** nicht stören: `WorldLevel.starting_health_ratio()` arbeitet auf dem Maximum; Stufe 1 = 100 → alles bleibt identisch.
- Bei `Neu beginnen`, Respawn und Dev-Heilen wird auf dem neuen Maximum geheilt.
- Der Dev-Tab bekommt Zeilen: „STUFE +1", „STUFE SETZEN …", „XP +100" für schnelles Testen.

---

## 8. Coole Extras (Ideenpool, einzeln wählbar)

1. **Chronik beim Zurückschwenken.** Zieht man das Fenster nach links, erscheint unter jeder erreichten Stufe eine kleine Notiz, wann und wodurch sie kam („Nacht 3 · Schattenspinne"). Billig (das `level_log`), aber erzählt die eigene Geschichte.
2. **Jahresringe.** Der Stumpf-Querschnitt unten links zeigt, woher die XP kamen. Bei Hover bunte Ringe: Gold = Kampf, Türkis = Stadt, Violett = Entdecken, Rot = Boss.
3. **Mitspieler auf der Ranke.** Im Koop sitzen die Stufen der Freunde als kleine Knospen in ihrer Farbe auf der Ranke. „Wer ist vorne" ohne Rangliste.
4. **Siegel am Himmel.** Meilensteine zünden ein Siegel in der Nachthimmel-Ecke des Fensters (das Siegel der Stufe bleibt dauerhaft sichtbar: sechs Siegel für Stufe 5, 10 … 30). Am Spielende hängt ein Kranz aus sechs Siegeln über der Ranke.
5. **Wetterleuchten.** Beim Öffnen reagiert der Schleier auf die Tageszeit: nachts Augen im Nebel, tags Pollen im Licht.
6. **Vorschau auf Wunsch.** Ein gehaltener Klick auf eine ferne Stufe „schiebt den Schleier weg" für einen Blick auf den Meilenstein (wie das Erkunden im Fähigkeitsgraph; kostenlos). Die Vorschau ist nur Schau, die Belohnung ändert sich nicht.
7. **Nach Stufe 30.** XP laufen weiter in „Schattenlicht"-Stufen (keine Werte, nur ein goldener Ring um die Blüte, ein Zähler, ein Titel pro 10 Ringe). Offen, ob gewollt.
8. **Erinnerungs-Fotos.** Jeder Meilenstein speichert beim Erreichen einen Mini-Schnappschuss des Bildschirms als Hintergrund der Karte (nur lokal, klein). Optional, nicht billig.

---

## 9. Tests

- `tools/test_levels.tscn` (headless): Kurve monoton, `level_for`/`xp_at` stimmig, `LevelRewards.stats_at` entspricht der Tabelle, Meilensteine genau einmal, Sprung über mehrere Stufen, Max-Stufe.
- **Balance-Bot** `tools/sim_levels.gd` (oder im selben Test): spielt Nächte als reine Zahlenrechnung (Budget, Kill-Anteil, Quellen) und druckt „Nacht je Stufe" und „Treffer bis Tod" für Spinne, Lauscher, Brecher. Grenzwerte als Asserts (z. B. Stufe 30 nicht vor Nacht 45, Stufe 5 nicht vor Nacht 3).
- `tools/test_progress_window.tscn`: Fenster öffnet/schließt (P, Esc, Klick aufs Abzeichen), Pan/Zoom, aktuelle Stufe zentriert, Zukunft verschleiert, neue Stufe öffnet Blüte, „NEU"-Knospe, gesperrt in Story/Tod, Pausemenü-Schaltfläche; Screenshots (weit/normal/nah, Tag/Nacht, Stufe 1/8/30).
- Netzwerk `tools/test_progress_network.tscn` (zwei Prozesse, freier Loopback-Port): Aufstieg am Host, Client sieht Maximum/Rüstung, Beitritt mitten im Spiel, Rüstung wirkt auf Host-Schaden.
- Regression: `test_story_start.tscn` (Wundstart), `test_night.tscn` (Budgets), Hotbar/XP-Ranke.

---

## 10. Reihenfolge (Vorschlag)

Du willst zuerst das Fenster. Damit es nicht leer ist, braucht es vorher ein Minimum an Daten, die Werte kommen danach:

1. **Daten & reine Logik** (klein): `levels.json`/`level_rewards.json`, `LevelRewards`, `test_levels`, Balance-Bot. Noch keine Spielwirkung. *Hier fällt auch die Entscheidung über die Kurve.*
2. **Fenster v1:** `PanZoomView`, `ProgressWindow` mit Schleier, Ranke, Belohnungs-Blättern, linker Karte, Pan/Zoom, Eingaben, HUD-Haken, Pausemenü-Button, Dev-Zeile „STUFE". Die Werte werden angezeigt, **wirken aber noch nicht** (markiert als „bald").
3. **Werte wirken:** Rüstung, Leben/Ausdauer-Maximum, Synchronisation, Stufenaufstieg heilt den Zuwachs, Balance-Test.
4. **Aufstiegs-Erlebnis:** Banner, Ringe, Töne, „NEU"-Knospe, Reveal im Fenster.
5. **XP-Quellen:** Kampf × Stärke, Quests, Entdeckungen, Stadt, Boss; Kurve nachjustieren.
6. **Echte Meilensteine** einzeln (Talisman-Plätze zuerst, sie sind schon da).
7. **Politur:** Chronik, Jahresringe, Mitspieler-Knospen, Siegel.

---

## 11. Offene Fragen an dich

1. **Taste und Name:** P und „FORTSCHRITT" – passt das? (Alternativ J für Journal.)
2. **Rüstung als neuer Wert:** gewollt? Formel `80 / (80 + R)`, Anzeige mit Prozent. Gibt es einen zweiten Verteidigungswert (z. B. gegen Brand), oder bleibt es bei einem?
3. **Tempo:** Stufe 30 nach ca. 60 Nächten (12 Std. Nächte) oder lieber länger/kürzer? Soll die Kurve früh fix sein?
4. **Max-Stufe 30** behalten? Und „Schattenlicht" danach (Extra 7)?
5. **Level macht Nacht schwerer** (Budget +10 %, Stärke +6 % je Stufe): behalten, abschwächen oder auf Tage umstellen? Beeinflusst die Balance der Rüstung.
6. **Zukunft im Fenster:** alle Meilensteine ab Stufe 1 sichtbar-verschleiert (motivierend) oder nur die nächsten ~5 (Überraschung)?
7. **Automatisch oder Abholen?** Belohnungen sofort (Vorschlag) oder Meilensteine mit „Halten zum Annehmen"?
8. **Aufstieg heilt?** Nur der Zuwachs (Vorschlag), zusätzlich ein Atemzug, oder voll?
9. **Fähigkeitspunkte:** 1 pro Stufe (wie angezeigt) in den Graphen übernehmen, wenn die Ausgabe dort gebaut wird?
10. **Meilenstein-Liste (Abschnitt 5):** was behalten, streichen, ersetzen? Welche eigenen Ideen willst du aufnehmen?
11. **Mitspieler sichtbar** (Extra 3) und öffentliche Stufenzahl: ok für Koop?
12. **Alte Spielstände:** durch die neue Kurve steigen sie in der Stufe – egal, oder soll ein Spielstand seine Stufe behalten (Skalierung der gespeicherten XP)?
