# Verfeinern (Refinement), Torbens 5. Reiter

Stand 2026-11-09. **Gebaut: Schritte 1 bis 6** (Regeln und Daten, die Stufe wandert mit dem Stapel, Wirkung im Kampf, Tooltip und Slot-Marke, Torbens Reiter, Enthüllungs-Karte, Klänge, Funken, Schimmer). Die Feinabstimmung der Zahlen (Schritt 7) folgt. Torbens Schmiede-Fenster (`torben_forge`, `docs/town.md`) bekommt den Reiter **VERFEINERN**: Waffen lassen sich von +0 bis +15 verfeinern. Jede Stufe macht die Waffe stärker und kostet mehr, ab +6 kann sie misslingen, die letzten fünf sind sehr schwer.

## 1. Kurzfassung

| Stufen | Name | Chance (Gerade) | Fehlschlag | Vertrauen |
|---|---|---|---|---|
| +1 bis +5 | Anschmieden | 100 % | gibt es nicht | 0 |
| +6 bis +10 | Härten | 85 % fallend auf 51 % | Material weg, **Hälfte vom Eisen zurück** | 20 |
| +11 bis +15 | Leerenschmieden | 42 % fallend auf **8 %** | Material weg, nichts zurück | 50 |

Die Obergrenze hängt an der Seltenheit (1a): gewöhnlich +5, ungewöhnlich +10, ab selten +15.

- **Eine Waffe verliert nie eine Stufe und geht nie kaputt.** Der Schmerz ist Material und Zeit (Simulation: ein Fall-zurück-Gesetz macht die letzten Stufen unspielbar, siehe 6).
- **Glut (Mitleid):** jeder Fehlschlag an derselben Stufe erhöht die nächste Chance (Härten +3 % je Fehlschlag, höchstens +15 %; Leerenschmieden +2 %, höchstens +12 %). Der Zähler hängt an der Waffe (`rp`), fällt auf 0, sobald die Stufe gelingt.
- Die Waffe wird **zu Torben gebracht** und liegt, während er arbeitet, auf dem Amboss (er arbeitet nur am Amboss, wie bei allen Aufträgen). Das Ergebnis steht **von Anfang an fest** (gewürfelt beim Abgeben, gespeichert), damit Neuladen nichts ändert.

### 1a. Seltenheit und Material gehören zusammen (beschlossen, neu abgestimmt)

**Obergrenze nach Seltenheit:** gewöhnliche Waffen bis +5, ungewöhnliche bis +10, ab selten bis +15 (`rarity.cap` in `data/refine.json`). Gewöhnlich und ungewöhnlich liegen dicht beieinander (dieselbe Materialleiter bis +5, Kosten x1,15, Chance x0,97, Dauer x1,05), selten, episch und legendär machen immer größere Sprünge.

**Gerade Kurven:** Die Chance fällt linear von 85 % bei +6 auf 8 % bei +15, Kupfer (`5,5 * Stufe * Seltenheit`), Arbeitszeit (`12 s * Stufe * Seltenheit`) und Schaden (+5 % je Stufe) steigen linear. Nur die Seltenheit springt.

**Materialleiter je Seltenheit** (`ladder`, Hauptmaterial / Nebenmaterial je Abschnitt +1..+5, +6..+10, +11..+15):

| Seltenheit | Obergrenze | +1..+5 | +6..+10 | +11..+15 | Kupfer | Dauer | Chance | Menge |
|---|---|---|---|---|---|---|---|---|
| gewöhnlich | +5 | Barren | (Platten / Barren) | (Splitter / Platten) | x1 | x1 | x1 | x1 |
| ungewöhnlich | +10 | Barren | Platten / Splitter | (Splitter / Platten) | x1,15 | x1,05 | x0,97 | x1 |
| selten | +15 | Platten / Barren | Splitter / Platten | Kerne / Splitter | x1,7 | x1,2 | x0,9 | x1,2 |
| episch | +15 | Splitter / Platten | Kerne / Splitter | Kerne / Schlacke | x3,2 | x1,5 | x0,78 | x1,6 |
| legendär | +15 | Kerne / Splitter | Schlacke / Kerne | Schlacke / Kerne | x6 | x1,9 | x0,65 | x2,2 |

(Eingeklammerte Abschnitte kann die Waffe wegen ihrer Obergrenze nie erreichen.) Ein Gegenstand kann `refine_cap` und `refine_ladder` (eine Seltenheit) selbst setzen. Leerenschlacke zählt wegen ihrer Seltenheit nur ein Fünftel (`item_amount`).

**Abstimmung gegen die echte Beute** (`python3 tools/sim_refine.py`, 20 000 Läufe: je Kill 7,9 Kupfer, 1,28 Splitter, 0,12 Kerne, 0,017 Schlacke, 16 Kills die Nacht, ein Fels gibt rund 4 Erz):

| Seltenheit | Versuche | Torben | Kupfer | Material (Mittel) | Eisen | Jagd |
|---|---|---|---|---|---|---|
| gewöhnlich, bis +5 | 5 | 3 Min (0,6 Tage) | 84 | 9 Barren | 4 Felsen | 1 Nacht |
| ungewöhnlich, bis +10 | 12,6 | 16 Min (3,3 Tage) | 491 | 9 Barren, 15 Platten, 11 Splitter | 14 Felsen | 4 Nächte |
| selten, bis +15 | 34 | 88 Min (18 Tage) | 3440 | 22 Platten, 62 Splitter, 33 Kerne | 15 Felsen | 27 Nächte |
| episch, bis +15 | 37 | 121 Min (24,5 Tage) | 7080 | 29 Splitter, 88 Kerne, 8 Schlacke | | 56 Nächte |
| legendär, bis +15 | 41 | 170 Min (35 Tage) | 14 770 | 87 Kerne, 36 Schlacke | | 136 Nächte (Schlacke) |

Das Geschmiedete Schwert kommt früh im Spiel und ist darum nach wenigen Tagen auf +10; die großen Brocken warten bei den selteneren Waffen. **Offen für spätere Waffen:** Leerenschlacke fällt nur beim Brecher (10 %) und beim Boss (30 %), die legendäre Leiter braucht deshalb über 130 Nächte. Vor der ersten legendären Waffe sollte die Schlacke-Beute steigen (Empfehlung: Brecher 25 %, die Mine eine Schlackeader).

## 2. Datenmodell

Ein Stapel ist `{"id", "count"}`. Neu: `"r"` (Stufe 0 bis 15, fehlt = 0) und `"rp"` (Fehlschläge an der aktuellen Stufe, fehlt = 0). Waffen haben `max_stack` 1, es gibt also nie Verwechslungen beim Stapeln.

- `data/items.json`: pro Waffe `"refinable": true` und optional `"refine_cap"` (Standard 15).
- `data/refine.json` (neu, einzige Quelle aller Zahlen): `tiers` (Namen, Vertrauen, Chance je Stufe, Glut-Schritt und -Grenze, Rückerstattung), `gain` (Prozent Schaden je Stufe), `perks` (Meilensteine), `cost` (Kupfer-Formel + Material je Stufe), `work` (Sekunden Arbeit je Stufe).
- `RefineRules` (rein, wie `TownRules` / `FishingRules`, voll testbar): `chance(level, pity)`, `cost(level)`, `work_seconds(level)`, `multiplier(level)`, `stat(stack, key)`, `roll(seed)`.
- `Items.refine(stack)`, `Items.stat(stack, key)` (Basiswert mal Verfeinerung), `Items.title(stack)` ("GESCHMIEDETES SCHWERT +7").

## 3. Stärke

Zuwachs: **+5 % des Basis-Schadens je Stufe**, linear (Rückstoß halb so viel): +25 % bei +5, +50 % bei +10, +75 % bei +15. Meilensteine als kleine Extras: **+5 Gehärtet** (Reichweite +1), **+10 Leerenfest** (Reichweite +1, schwacher Schimmer der Klinge), **+15 Vollendet** (Reichweite +1, Tempo +5 %, leuchtende Schneide).

Beispiele (Schaden): Einfaches Schwert 5 -> 6,25 (+5), Geschmiedetes 8 -> 12 (+10), Leerenklinge 30 -> 52,5 (+15). Das Einfache Schwert bleibt damit unter einem neuen Geschmiedeten (8).

## 4. Kosten je Versuch (Geschmiedetes Schwert)

Kupfer = `5,5 * Stufe * Seltenheitsfaktor` (6 bei +1, 32 bei +5, 63 bei +10, 95 bei +15 für ein Geschmiedetes Schwert). Material je Versuch laut Leiter (1a), die Mengen steigen innerhalb eines Abschnitts von 1 auf 3.

| Stufe | Kupfer | Dauer | Chance | Eisenbarren | Eisenplatten | Leerensplitter | Schattenkern | Leerenschlacke |
|---|---|---|---|---|---|---|---|---|
| +1 | 6 | 13 s | 100 % | 1 |  |  |  |  |
| +2 | 13 | 25 s | 100 % | 1 |  |  |  |  |
| +3 | 19 | 38 s | 100 % | 2 |  |  |  |  |
| +4 | 25 | 50 s | 100 % | 2 |  |  |  |  |
| +5 | 32 | 63 s | 100 % | 3 |  |  |  |  |
| +6 | 38 | 76 s | 82 % |  | 1 | 1 |  |  |
| +7 | 44 | 88 s | 74 % |  | 1 | 1 |  |  |
| +8 | 51 | 101 s | 66 % |  | 2 | 1 |  |  |
| +9 | 57 | 113 s | 58 % |  | 2 | 2 |  |  |
| +10 | 63 | 126 s | 49 % |  | 3 | 2 |  |  |

## 5. Zeit

Torben arbeitet nur am Amboss (ein Spieltag gibt ihm rund 295 s Arbeit). Arbeitszeit je Versuch: **12 s mal Stufe mal Seltenheitsfaktor**, also linear von 12 s bei +1 bis 180 s bei +15 (ungewöhnlich x1,05). Das passt zur Auftragswarteliste (3 Plätze, die Schmiede hat ihre eigene), das Fenster zeigt wie bei Bestellungen die Dauer. Erwartung je Seltenheit: Tabelle in 1a.

## 6. Warum kein Fall zurück

Simuliert: fällt die Waffe beim Fehlschlag ab +14 um eine Stufe (Boden +12), brauchen die letzten Stufen im Mittel 172 Versuche statt 29, ab +15 59. Das ist ein Kreislauf aus Aufsteigen und Zurückfallen, der unspielbar wird und die Spielerin bestraft statt belohnt. Wer das wollte, könnte später **Schutzzunder** (Harz + Leerenschlacke, bei Torben ab Vertrauen 70 gekauft) einführen, der nur bei einem Modus mit Verlust Sinn macht. Standard bleibt: Material weg, Stufe bleibt.

## 7. Der Ablauf im Fenster

Reiter 5 **VERFEINERN** in `ShopWindow` (neue `kind: "refine"`):

1. **Liste:** alle verfeinerbaren Waffen im Rucksack und die angelegte (Zusatz "ANGELEGT"). Jede Zeile: Symbol mit gelber "+7"-Marke, Name, "+7 -> +8", Chance farbig (grün ab 70 %, gold ab 30 %, rot darunter). Unter dem Stapel liegen die Aufträge auf dem Amboss (Fortschrittsbalken, "ARBEITET DARAN", "FERTIG, ABHOLEN").
2. **Detail:** links die Waffe groß, rechts Schaden alt -> neu (und Reichweite, falls ein Meilenstein erreicht wird), **Chance-Leiste** mit Glut-Anteil in Gold, Material-Chips wie bei Bestellungen (rot, was fehlt), Kupfer, Dauer. Torben spricht sein Urteil als Zeile (3 bis 5 Worte): "Hält." (>70 %), "Riskant." (30 bis 70 %), "Schrott." (<30 %), bei +15 "...Ja. Noch einmal.".
3. **VERFEINERN:** Waffe und Material verlassen den Rucksack sofort, ein Auftrag `{k: "refine", stack, to, left, total, ok}` landet in der Warteliste der Schmiede. Ein Hinweis warnt, wenn es die einzige Waffe ist.
4. **Ergebnis:** beim Fertigwerden ruft Torben das Banner ("..." Platzhaltertext), das Stück liegt auf der Bank. ABHOLEN gibt die Waffe zurück; erst dann zeigt eine **Enthüllungs-Karte** das Ergebnis: Erfolg mit Funken und Glocke, Fehlschlag mit Zischen, Wölkchen und "GLUT +3 %".

Vertrauens- und Stufenhürden: Härten ab Vertrauen 20, Leerenschmieden ab 50 (Vertrauen wächst um 10 je Tag mit einem Gespräch). Mehrspieler: Auftrag und Waffe gehören der Stadt, wie bei Bestellungen, jede kann abholen.

## 8. Darstellung

- **Tooltip** (`ItemTooltip`): Name mit Marke "+7", darunter eine **Perlenreihe aus 15** (Lücken nach 5 und 10, gefüllt bis zur Stufe, Farbe nach Abschnitt: Stahl, Türkis, Gold-Magenta; bei +15 pulsieren alle), Werte als "SCHADEN 12,0 (+4,0)", Meilenstein-Zeilen als Kleingedrucktes ("+5 GEHÄRTET REICHWEITE +1", ausgegraut bis erreicht).
- **Slot** (`ItemSlot`): kleine "+7" unten rechts in der Farbe des Abschnitts (wie der Stapelzähler).
- **Waffe in der Hand:** +10 schwacher Rand-Schimmer, +15 leuchtende Schneide (gleiche Technik wie die Leuchtbilder anderer Gegenstände, nur ein Aufsatz auf dem gehaltenen Bild, nichts am Würfelbild).
- **Torben:** der Hammerschlag-Clip `work` (strike 4) bekommt Funken in der Stärke der Stufe, beim Fertigwerden `quench` mit Zischen. Neue Klänge `tools/audio_refine.py` (Glut, Abschrecken, Erfolgsglocke, Fehlschlagzischen, Vollendung).

## 9. Technische Berührungspunkte

Das Verfeinern hängt an einem einzigen Risiko: **der Stapel muss `r` und `rp` unversehrt durch alles tragen.** An diesen Stellen werden Stapel heute neu aus `id` und `count` gebaut und müssen angepasst werden: `InventoryComponent` (Verschieben, Anlegen, Tauschen, Halbieren, `held`, Spiegel an den Besitzer), `DropComponent.spawn_thrown` / `ItemDrop` (weggeworfene Waffe), `SaveGame` (angelegte Ausrüstung wird bisher nur als `id` gespeichert), `QuestComponent`-Zähler (`count_item`, unberührt). Der Schaden folgt `Items.stat` statt `def.stats` in `AttackComponent` (`_hit_scan`, `_reach`, Tempo; die Ausführung läuft auf dem Host).

Neu: `RefineRules`, `data/refine.json`, `ShopWindow` `kind: "refine"` plus Auftragsart in `TownManager` (`request_refine`, Würfeln beim Abgeben mit gespeichertem Ergebnis, `_work_orders` unverändert, `_host_collect` gibt den Stapel zurück), Banner, Enthüllungs-Karte, `tools/sim_refine.py`.

## 10. Bauplan

1. **Regeln und Daten:** `refine.json`, `RefineRules`, Simulation, Test der Kurven (Chancen, Kosten, Glut, Stärke).
2. **Stapel trägt `r` / `rp`:** `Items`, `InventoryComponent`, Wurf, Speichern, Spiegel; Test mit Anlegen, Wurf, Speichern und Laden.
3. **Wirkung:** `AttackComponent` nimmt verfeinerte Werte; Entwickler-Knopf "WAFFE +N" im Menü.
4. **Anzeige:** Tooltip, Marke im Slot, Name mit Marke.
5. **Torbens 5. Reiter:** `kind: "refine"`, Auftrag, Host-Regeln, Vertrauen, Urteilszeilen; Test wie `test_smithy_shop`.
6. **Gefühl:** Enthüllungs-Karte, Klänge, Funken im Hammerclip, Schimmer ab +10, Leuchten bei +15.
7. **Feinabstimmung:** Simulation gegen echte Drop-Raten, Preise gegen die Wirtschaft.

Später (nicht jetzt): Werkzeuge und Rüstung (`refinable` setzen), Schutzzunder, eine Abschreck-Geste als Geschicklichkeitsbonus (+ bis 5 Punkte Chance, Timing wie beim Kochen und Angeln).

## 11. Entscheidungen

Alle vier sind entschieden (2026-11-09): 1. die Obergrenze hängt an der Seltenheit (gewöhnlich +5, ungewöhnlich +10, ab selten +15), 2. Fehlschlag ohne Stufenverlust, 3. die Waffe wird abgegeben und kommt später zurück, 4. die Abschreck-Geste kommt erst später.
