# Alchemie – Konzept (Entwurf, 2026-11-10)

Status: **Konzept, nichts gebaut.** Ersetzt das Kochen vollständig. Entscheidungen vom 2026-11-10 sind eingearbeitet (Abschnitt 10).

## 1. Idee in einem Satz

Ellie braut bei **Esma, der Nebelhexe**, aus Kräutern, Beeren, Pilzen und Wurzeln **Tränke in fünf Stufen**; zum Start gibt es zwei: einen **Heiltrank** (sofortige Heilung) und einen **Ausdauertrank** (30 s lang jede Sekunde Ausdauer), beide im Kampf in einer schnellen Trink-Animation nutzbar.

## 2. Warum Alchemie statt Kochen

- Shadowspore tötet keine Tiere. Kochen ohne tierische Zutaten bleibt dünn, Alchemie lebt dagegen genau von dem, was die Welt schon im Überfluss hat: Wundblatt, Mondglocke, Glutbeeren, Nebelblüten, Alraunen, Leerenblüten.
- Sie gibt den vielen Pflanzen-Items einen Zweck. Die meisten sind heute „material“ ohne Verwendung.
- Sie passt zu Esma, zum Hexenwald und zur Leere: Tränke sind eingefangenes Licht gegen die Nacht.

## 3. Kochen entfernen

Komplett raus, nichts davon bleibt spielbar:

| Was | Datei(en) |
|---|---|
| Logik | `src/systems/cooking_session.gd`, `cooking_timing.gd`, `cooking_book.gd` |
| UI | `src/ui/cooking_window.gd`, Dev-Eintrag KOCHPLATZ in `src/ui/pause_menu.gd` |
| Daten | `data/cooking.json` |
| Tests/Doku | `tools/test_cooking.tscn/.gd`, `docs/cooking.md`, Abschnitt in `CLAUDE.md` |
| Verweise | `world_level.gd`, `knight_fire_scene.gd` (Flag `knows_cooking`), `fish_book.gd`, `test_debug_wake.gd` |
| Kochassets | die Kochplatz-Bilder und Kochgeräusche (vorher prüfen, was geteilt ist) |

- `user://cooking_book.json` wird nicht mehr gelesen; alte Saves laden ohne Fehler.
- Valdrics leuchtender Becher am Feuer bleibt als Story-Moment (das ist kein Kochen). Die Flag `knows_cooking` fällt weg.
- **Was wir mitnehmen:** höchstens die Dampf- und Gieß-Animationen für den Kessel-Moment im Alchemie-Tab (6.3). Journal und Timing-Geste fallen weg, weil Esma braut.

## 4. Die Tränke

### 4.1 Gemeinsame Regeln

- Neue Item-Art `kind: "potion"`, `hotbar: true`, **`max_stack: 10`**.
- Jede Stufe ist ein eigenes Item (`potion_heal_1` … `potion_heal_5`, `potion_stamina_1` … `_5`). Dadurch stapeln sie sauber, Tooltip, Preis und Seltenheit hängen an der ID. Jede bekommt einen Block `potion: {type, tier}`.
- Seltenheit folgt der Stufe: I common, II common, III uncommon, IV rare, V epic.
- **Stufennamen** (zeigen, wie stark der Sud leuchtet): **I TRÜB · II KLAR · III LEUCHTEND · IV STRAHLEND · V MEISTERSUD**. Das Icon zeigt es: Füllstand und Leuchten steigen, der Verschluss wird edler (I Korken, II Korken mit Schnur, III Wachssiegel, IV Silberkappe, V Silberkappe mit glimmender Rune).

### 4.2 Heiltrank – „Wundtau“ (Farbe: rosiges Rot, wie der Saft der Lebensranke)

Heilt **sofort**. Weil die maximale Gesundheit mit den Stufen wächst (100 → ca. 240 auf Stufe 30), heilt der Trank einen **Anteil der maximalen Gesundheit mit Mindestwert**. So bleibt Stufe I nie nutzlos, und Stufe V bleibt im Spätspiel stark.

| Stufe | Heilung | Extra |
|---|---|---|
| I TRÜB | 20 % (mind. 20) | – |
| II KLAR | 30 % (mind. 30) | – |
| III LEUCHTEND | 40 % (mind. 45) | – |
| IV STRAHLEND | 55 % (mind. 60) | löscht VERBRENNEN |
| V MEISTERSUD | 70 % (mind. 80) | löscht VERBRENNEN, Überschuss wird Überheilung (vorhandenes System) |

- **Wundpause:** nach einem Heiltrank wirkt der nächste Heiltrank erst nach **10 s**. Sie wird als HUD-Tag „WUNDPAUSE“ angezeigt (`StatusTags`). Sie verhindert, dass man Tränke im Kampf hintereinander kippt, statt auszuweichen.
- Bei voller Gesundheit wird nichts verbraucht (wie bei Beeren, `HealthComponent.can_heal`). Ausnahme: Stufe V, solange noch Überheilung möglich ist.

### 4.3 Ausdauertrank – „Glutatem“ (Farbe: Bernstein-Gold mit Funken)

**30 s lang, jede Sekunde** ein Schub Ausdauer.

Problem: Ausdauer lädt schon von selbst schnell nach (25/s nach 1,25 s Pause). Ein Trank, der nur „mehr Nachladen“ gibt, wäre kaum zu spüren. Deshalb:
**Die Schübe des Trankes kommen auch während der Nachlade-Pause.** Damit trägt er genau dann, wenn man rennt, ausweicht oder Wuchtschläge führt, also wenn die normale Regeneration stillsteht.

| Stufe | pro Sekunde | gesamt (30 s) | Extra |
|---|---|---|---|
| I | 3 | 90 | – |
| II | 5 | 150 | – |
| III | 7 | 210 | – |
| IV | 9 | 270 | Nachlade-Pause −25 % |
| V | 12 | 360 | Nachlade-Pause −50 %, Sprint verbraucht −15 % |

- Ein neuer Ausdauertrank **ersetzt** den laufenden (die stärkere Stufe gewinnt, die Zeit beginnt neu). Sie stapeln sich nicht.
- Umgesetzt als Status-Effekt `glutatem` in `data/status_effects.json` mit Tag im HUD und einem dünnen Bernstein-Schimmer an der Ausdauerranke, solange er wirkt.

## 5. Ellie trinkt – Animation und Bedienung

### 5.1 Die Animation „Schluck“ (schnell, kampftauglich)

Gesamt **0,6 s**, Wirkung bei **0,30 s** (der Schluck). Zum Vergleich: Essen dauert 1 s, Wirkung bei 0,48 s.

1. 0,00 – Die linke Hand reißt die Phiole vom Gürtel.
2. 0,10 – Den Korken schnippt sie mit dem Daumen ab (kleines „Plopp“, der Korken fliegt als Partikel).
3. 0,18 – Den Kopf wirft sie zurück, die Phiole an den Lippen, ein Schluck in einem Zug. **0,30 = Wirkung.**
4. 0,40 – Sie wischt sich mit dem Handrücken den Mund. Die leere Phiole wirft sie hinter sich, sie zerspringt am Boden in ein paar Glassplitter-Pixel.
5. 0,60 – Fertig.

- Pfad: `Player._begin_action("drink", …)`, wie Essen und Pflücken. Neues Sheet **`player_drink.png`** (Sheet 15) mit **7 Bein-Varianten** wie beim Essen: **sie kann beim Trinken gehen** (nicht sprinten). Rig-Punkt `drink_mouth` für die Effekte.
- Das Schwert bleibt in der rechten Hand (der Schwertarm ist ja nicht im Sheet). Sie trinkt links, deshalb muss die Waffe nicht weggesteckt werden. Das macht es schnell und sieht im Kampf richtig aus.
- **Unterbrechung:** Leichte Treffer unterbrechen **nicht**. Nur schwerer Rückstoß (≥ `heavy_knockback`) vor dem Schluck unterbricht, dann bleibt der Trank erhalten.
- **Wirkung sichtbar** (`DrinkEffect`, src/fx, nach dem Vorbild von `EatEffect`): Heiltrank = rosiges Licht läuft ihr vom Mund durch den Körper nach unten, kurzer Puls an der Lebensranke. Ausdauertrank = goldene Funken steigen von den Füßen auf, die Ausdauerranke glüht kurz auf. Alles über die Animationszeit getaktet, damit jeder Peer dasselbe sieht.
- Kunst: neuer Pose-Zeitstrahl `DRINK_KEYS` in `tools/art_hero3d.py` (`drinkonly`, wie `feedonly`), die Phiole als optionaler Pose-Schlüssel `vial` (wie `mug` beim Sitzen). Blut-Sheet und Schmuckpunkte (`art_hero_jewelry.py`) mitziehen. Laut Projektregel macht das ein Art-Subagent.

### 5.2 Bedienung

- Tränke sind **normale Inventar-Items** und werden genau wie Beeren benutzt: im Hotbar-Slot wählen, dann **E** (wenn nichts Benutzbares in Reichweite ist) oder **die Zahlentaste des schon gewählten Slots** (`Player.use_slot`). Keine eigene Taste.
- Die Hotbar zeigt an Trank-Slots die Wundpause als sich füllenden Ring.

### 5.3 Esspause für Beeren und Co. (neu, gilt auch für alles Essbare)

- Nach dem Essen eines `consumable` (Dämmerbeere, Glutbeere, Wundblatt, Farnspross, Erdknolle, Nachtrübe …) kann **3 s lang nichts anderes gegessen** werden (`food_pause`).
- Ess- und Wundpause sind **getrennt**: Eine Beere blockiert keinen Heiltrank und umgekehrt. So bleibt der Trank der Notfallknopf.
- Umsetzung auf dem Host in `InventoryComponent._use` (Zeitstempel pro Spieler, Wert in den Daten, z. B. `data/alchemy.json` `pauses {food: 3.0, heal_potion: 10.0}`). Startet der Spieler das Essen während der Pause, beginnt die Animation gar nicht erst, und der Slot ruckt kurz (wie bei voller Gesundheit). Dieselbe Ring-Anzeige wie bei der Wundpause an den Slots mit Essbarem.

## 6. Brauen bei Esma

### 6.1 Der Tab ALCHEMIE

`data/shops.json` → `witch_counter` bekommt einen fünften Tab `{"id": "brew", "name": "ALCHEMIE", "kind": "brew"}`, gebaut als neuer Tab-Typ in `ShopWindow` (wie VERFEINERN).

**Esma braut, nicht Ellie.** Ellie bringt Zutaten und Phiolen, Esma macht den Sud. Einen eigenen Kessel für Ellie oder andere Brauorte gibt es vorerst nicht.

Aufbau der Seite:
- **Links die Trankliste**: Wundtau, Glutatem (später mehr). Jeder Trank hat fünf **Stufen-Perlen**: gesperrt = Knospe, freigeschaltet = offen (wie die `BloomOrb`-Blüten).
- **Rechts das Rezept** der gewählten Stufe: Zutaten als `ItemSlot`-Reihen mit „hast / brauchst“, darunter Wirkung und Ausbeute.
- Knöpfe: **BRAUEN LASSEN** (A/D wechselt die Stufe, Shift = so oft wie möglich).

### 6.2 Zutaten und Rezepte

Jedes Rezept braucht eine **Leere Phiole** (`vial_empty`, bei Esma 4 Kupfer, stapelbar 20) plus Zutaten. Die Stufen werden teurer und brauchen seltenere Sachen. Ab Stufe IV braucht man einen **Katalysator** (Leerenblüte, Alraune, Schattenkern): eine Brücke zum Hexenwald und zu den Schattenkreaturen.

**Wundtau (Heilung)** – Grundlage: Wundblatt

| Stufe | Zutaten |
|---|---|
| I | 3 Wundblatt, 2 Dämmerbeere |
| II | 4 Wundblatt, 2 Mondglocke, 1 Sonnenkern |
| III | 4 Wundblatt, 2 Sonnenkern, 2 Nachtrübe, 1 Nebelblüte |
| IV | 5 Wundblatt, 3 Nachtrübe, 2 Nebelblüte, 1 Irisblüte, 1 Leerenblüte |
| V | 6 Wundblatt, 3 Nebelblüte, 2 Irisblüte, 1 Alraune, 1 Schattenkern |

**Glutatem (Ausdauer)** – Grundlage: Glut-Pflanzen und Minze

| Stufe | Zutaten |
|---|---|
| I | 3 Glutbeere, 2 Bachminze |
| II | 3 Glutbeere, 3 Bachminze, 2 Mohnfunke |
| III | 2 Glutmöhre, 3 Bachminze, 2 Glutmorchel, 1 Sumpfdotter |
| IV | 3 Glutmöhre, 3 Glutmorchel, 2 Mondschirm, 1 Krötenschirm |
| V | 4 Glutmöhre, 3 Mondschirm, 2 Krötenschirm, 1 Alraune, 1 Schattenkern |

Rezepte stehen in einer neuen Datei **`data/alchemy.json`**, gelesen von einem reinen `AlchemyRules` (src/systems): Rezept, Freischaltung, Ausbeute. Die Zahlen sind ein erster Wurf und werden nach dem ersten Spieltest mit einem kleinen Sim-Skript (wie `sim_refine.py`) gegen die echte Pflanzendichte abgeglichen.

### 6.3 Der Brauvorgang – Esma am Kessel

**Sofort, wie das Verfeinern**, ohne Wartezeit und ohne Minispiel. **Ein Sud misslingt nie.**

1. BRAUEN LASSEN: Esma wendet sich zum Kessel (ihr `stir`-Clip aus dem Hexen-Sheet). Die Zutaten fliegen nacheinander als Icons hinein (der Kessel im Turmzimmer animiert schon Flammen, Sud und Dampf). Bei jeder Zutat verfärbt sich der Sud ein Stück Richtung Trankfarbe. Das dauert etwa 2 s und ist mit E/Klick überspringbar.
2. Esma füllt ab: Die Phiolen ploppen mit Korken in Ellies Tasche, das Ergebnis-Kärtchen erscheint (wie `RefineReveal`) und Esma sagt einen Satz (Platzhalter `brew` in den Laden-Zeilen).

- **Ausbeute:** 2 Tränke pro Sud (Stufe V: 1).
- Host-autoritär wie das Verfeinern: `TownManager.request_brew(recipe, tier, shop_id)` prüft Nähe, Vertrauen und Zutaten, nimmt sie und legt die Tränke in die Tasche. Ist die Tasche voll, fallen die Tränke als `ItemDrop` vor ihr auf den Boden.

### 6.4 Freischaltung und Rezeptbuch

- **Stufen schaltet Esmas Vertrauen frei** (vorhandenes System, +10 pro Tag Gespräch): **I 0 · II 10 · III 25 · IV 40 · V 60.** Dazu muss man die Stufe darunter mindestens einmal gebraut haben. Sie bringt es einem Schritt für Schritt bei.
- **Rezeptbuch** (ersetzt das Kochbuch): eine zweite Seite im Tab mit allen bekannten Tränken, Stufen und Zutaten, der Zahl der gebrauten Tränke und Esmas Randnotizen (Platzhalter für den Dialog-Autor). Gespeichert im Spielstand des Spielers (`player.alchemy`), nicht mehr als eigene user://-Datei, damit es im Mehrspieler zum Spieler gehört.

### 6.5 Esma als Lehrerin – kleiner Einstieg

Beim ersten Öffnen des Tabs eine kurze Lehr-Szene (Dialog `alchemy_intro`, Texte Platzhalter): Esma erklärt, was sie braucht, braut den ersten Wundtau I vor Ellies Augen und schenkt ihr **5 leere Phiolen**. Flag `alchemy_learned`. Eine größere Quest daraus machen wir später, wenn die Story bis zu Esma reicht.

## 7. Eigene Ideen (Vorschläge, einzeln abwählbar)

1. **Wundpause statt Trinklimit:** keine harte Mengenbremse, der Stack von 10 und die 10-s-Pause reichen.
2. **Die geworfene Phiole:** Die zerspringende Phiole ist ein kleiner, lebendiger Moment. Später könnte man die Scherben auch als Splitter aufsammeln und zu Esma zurückbringen (−1 Kupfer pro Phiole). Erstmal nur Effekt.
3. **Mond-Sud:** Was Esma nachts bei Vollmond braut, gibt +1 Trank (nutzt `TimeManager.moon_phase()`). Gibt der Nacht einen Grund, zu ihr zu gehen.
4. **Ausblick auf weitere Tränke**, die gut zu Systemen passen, die es schon gibt (nicht jetzt bauen):
   - **Klarblick:** hebt `hallucinated` im Hexenwald-Nebel für 60 s auf (eine Alternative zu den Ohrringen).
   - **Glutschutz:** halbiert VERBRENNEN, gut gegen Mornaths Phase 3.
   - **Lichtsud:** Ellie leuchtet 45 s lang schwach, Schattenkreaturen zögern (passt zu „Licht ist Land“).
   - **Schleichtrank:** kleinerer Alarmradius (`StealthComponent.alarm_scale`).
   - **Atemtrank:** längeres Kraulen beim Schwimmen.
5. **Andere Brauorte später:** vorerst nur bei Esma. Später vielleicht ein Kessel als Stadtgebäude (Bau-Katalog), der nur bis Stufe III braut.

## 8. Technik – wo es andockt

| Teil | Wo |
|---|---|
| Items | `data/items.json`: 10 Tränke + `vial_empty`, `kind: "potion"`, `max_stack: 10`, Block `potion` |
| Rezepte, Stufen, Freischaltung | `data/alchemy.json`, `AlchemyRules` (rein, getestet) |
| Benutzen | `InventoryComponent._use`: Zweig `potion` (Host) → `HealthComponent.heal` / Status `glutatem`; Wundpause (10 s, Heiltränke) und Esspause (3 s, alles `consumable`) als getrennte Pausen |
| Ausdauer-Schub | `StaminaComponent`: neue Funktion `boost(amount)`, die auch während `regen_delay` wirkt; Pause-Faktor für Stufe IV/V. Zu prüfen: wo die Ausdauer gezählt wird (Besitzer oder Host), der Effekt muss dort laufen |
| Animation | `Player._begin_action("drink")`, Sheet 15, `DRINK_USE_TIME` 0,30, `DrinkEffect` |
| Eingabe | keine neue Action: E / Zahlentaste über `Player.use_slot`, wie bei Beeren |
| Esma | `shops.json` Tab `brew`, `ShopWindow`-Zweig, `TownManager.request_brew` |
| Speichern | `player.alchemy` (gebraute Stufen, Zähler) in `SaveGame` |
| Kunst | Trank-Icons (`tools/art_potions.py`), Trink-Sheet + Phiole im Modell (Art-Subagent), Kessel-Einwurf/Rühr-Effekte im Tab |
| Ton | `tools/audio_alchemy.py`: Korken-Plopp, Schluck, Glas zerspringt, Blubbern, Einwurf, Gold-Rühren |
| Tests | `tools/test_alchemy.tscn` (Regeln, Rezepte, Stapel, Wundpause, Ausdauer-Schub, Host-Prüfung, Speichern), Netzwerk-Check für Trinken |

## 9. Bauplan (Reihenfolge)

1. Kochen entfernen (Abschnitt 3), Projekt startet ohne Fehler.
2. Items, `alchemy.json`, `AlchemyRules`, Benutzen inkl. Wundpause, Esspause und Glutatem, mit Platzhalter-Icons und der Ess-Animation als Stellvertreter. Test.
3. Trink-Animation + `DrinkEffect`.
4. Alchemie-Tab bei Esma, Brauen, Rezeptbuch, Lehr-Szene.
5. Icons, Töne, Feinschliff, Balancing.

## 10. Entscheidungen (2026-11-10)

1. **Phiolen** sind eine Zutat und werden bei Esma gekauft.
2. **Heilung in Prozent** der maximalen Gesundheit mit Mindestwert.
3. **Wundpause 10 s** für Heiltränke; zusätzlich **3 s Esspause** für Beeren und alles andere Essbare (5.3).
4. **Keine eigene Trank-Taste:** Tränke sind normale Inventar-Items, benutzt mit E oder der Zahlentaste des gewählten Slots.
5. **Esma braut** (Tab bei ihr), kein Rühren, kein Minispiel.
6. **Namen** Wundtau / Glutatem und TRÜB … MEISTERSUD bleiben.
7. **Angeln / Blattkrabbler als Köder** vs. „keine Tiere töten“: vorgemerkt, wird später angegangen, jetzt keine Änderung.

## 11. Drei besondere Tränke (gebaut 2026-11-10)

Wundtau und Glutatem sind die Alltagstränke (5 Stufen, Zahlen steigen). Die drei hier sind **Spezialtränke**: Sie lösen je ein Problem, das es im Spiel schon gibt, und haben einen Preis oder eine Bedingung. Sie haben nur **3 Stufen** (TRÜB / KLAR / MEISTERSUD), Stack 5 statt 10, brauchen seltene Zutaten und ein eigenes Esma-Rezept (Freischaltung über Quest oder Vertrauen). Alle laufen als Status-Effekte (`data/status_effects.json`, `tiered: true`, Tag mit „STUFE n“ im HUD) und teilen sich **eine Spezialpause** von 20 s, sonst trinkt man alle drei gleichzeitig.

### 11.1 Aschenhaut (Farbe: glimmendes Orange-Schwarz)
- **Problem, das es löst:** VERBRENNEN (Mornath Phase 3, Feuerboden, `FireArena`).
- **Wirkung 60 s:** Brandschaden × 0,6 / 0,4 / 0,2; Stufe III macht gegen den Brandboden komplett immun, aber nicht gegen Direkttreffer. Ein laufender Brand wird beim Trinken gelöscht.
- **Preis:** Ellie ist in der Zeit **wasserscheu**: Wasser (Waten, Schwimmen) löscht die Aschenhaut sofort. Man muss also vor dem Boss trinken und darf nicht durch den Fluss.
- **Zutaten:** Glutbeere, Embermorchel, Fluchsilber-Staub (III). Freischaltung nach der Mornath-Quest.
- **Technik:** `HealthComponent.take_tick` fragt `effects.scale_of("ashen")`; `Terrain submerge` > 0 räumt den Effekt weg (wie `_wet()` bei burn). Look: schwarze Glutadern am Körper (Shader `soak` in umgekehrter Farbe).

### 11.2 Klarblick (Farbe: Hexengrün mit weißem Kern)
- **Problem, das es löst:** HALLUZINIERT im Hexenwald-Nebel (Alternative zu den Ohrringen der Klarheit).
- **Wirkung 90 s:** entfernt `hallucinated` und verhindert es; Lügen der Lebensranke, Phantomspinnen und falsche Funde verschwinden. **Mehr als die Ohrringe:** echte Dinge funkeln schwach (pflückbare Hexenwald-Pflanzen, Truhen, Fallen), Stufe III zeigt zusätzlich Schattenkreaturen im Nebel als schwache magentafarbene Augen (wie `PetGlint`).
- **Preis:** Nur in Gebieten mit Nebel nützlich; außerhalb passiert nichts außer dem Funkeln. Dafür bleibt der Nebel im Kopf „sauber“: ein Hexen-Tipp für Esma-Quests.
- **Zutaten:** Geisterfarn, Mandragora (III), Nebellilie. Freischaltung: Esma-Quest nach der Spiegelhexe.
- **Technik:** Zweig in `StatusEffects._breathe_mist` (wie `clear_sight`), `Hallucinations` bleibt aus; Funkeln über die Gruppe `interactables` + lokale Zeichnung (nur Besitzer).

### 11.3 Irrlichtsud (Farbe: kaltes Türkis, wie die Stadtlampen)
- **Problem, das es löst:** Nacht außerhalb des Stadtlichts („Licht ist Land“).
- **Wirkung 45 s:** Ellie trägt ein kleines wanderndes Licht (`NightLight`, folgt ihr mit Verzögerung). Schattenkreaturen in seinem Radius **zögern** (sie behandeln es als Rand der Stadt: `NightBehavior` bleibt am Lichtrand stehen), `TownManager.light_depth` bekommt für sie einen weichen Kreis um sie; Stufe III lässt sie 3 s lang sogar zurückweichen.
- **Preis:** Der Lichtfischer fällt darauf herein (sein Köder imitiert Stadtlampen) und greift sie an, und Wildtiere (Rehe, Eulen) meiden sie. Außerdem sieht man sie von weit weg: Das **Lockmaß** der Nacht (`NightDirector.stir`) steigt langsam. Sicher heißt hier nicht unsichtbar.
- **Zutaten:** Leuchtmorchel, Glimmkappe, Sumpfgold; III braucht einen Schattenkern. Freischaltung über Vertrauen 40.
- **Technik:** `NightLight` an der Spielerin, Gruppe `player_lights`; Kreaturen prüfen sie in `NightBehavior.limit`; Look: Phiole leuchtet, ein einzelner Funke umkreist sie.

### 11.4 Reihenfolge, wenn ihr sie baut
Aschenhaut zuerst (kleinster Eingriff, direkt am Boss prüfbar), dann Klarblick, zuletzt Irrlichtsud (greift in die Nacht-KI ein, braucht Balancing). Jeder braucht Items + Rezepte in `alchemy.json`, Status-Eintrag, Icon (`art_potions.py`) und einen Dev-Button (der Button „ALLE TRÄNKE“ zählt sie über `AlchemyRules.TYPES` dann mit).

### 11.5 Wie es gebaut wurde (Abweichungen vom Konzept)
- **Eigene Herstellungswege** (`alchemy.json` `condition`, `AlchemyRules.condition_block`, `TownManager.brew_block`): Aschenhaut nur mit **fertiger Schmiede** in der Stadt, Klarblick nur im **Morgentau** (`TimeManager.dew_amount`, ca. 5 bis 9 Uhr), Irrlichtsud nur **bei Nacht**. Esmas Tab zeigt den Grund in Rot. Vertrauen: Aschenhaut 15/35/55, Klarblick 20/40/60, Irrlichtsud 10/30/50. Eine Freischaltung per Quest ist noch nicht gebaut.
- **Ein Glas für alle:** `tools/art_alchemy_icons.py` zeichnet dieselbe Phiole mit eigenem Sud und je einem Motiv (Glutfunken, grüner Kern, freies Irrlicht). Drei Stufen spielen wie Stufe 1, 3 und 5 der Alltagstränke (Füllstand, Siegel).
- **Wirkungen:** `StatusEffects` (`ashen`, `clear_vision`, `wisp`, `special_pause`), Aschenhaut senkt Brandschaden (`burn` 0,6/0,4/0,2) und macht auf III immun gegen das Anzünden, Wasser löscht sie (`extinguish`). Klarblick hält `hallucinated` fern (`_breathe_mist`). Irrlichtsud: `NightBehavior._wisp_say` bremst Kreaturen im Radius (40/52/64 px) und drängt sie auf III zurück, jede Sekunde steigt `NightDirector.stir` (der Preis).
- **Eigene Effekte:** `PotionFx` (src/fx) zeichnet Ruß/Glut, Funkeln über Pflückbarem und Augen im Nebel (III), das kreisende Irrlicht mit echtem `NightLight`. `DrinkEffect` hat je eine eigene Trink-Wirkung (Rußwelle, Linsenring, Funkenflug) und eigene Klänge (`tools/audio_alchemy.py`: ashen, clarity, wisp).
- **Test:** `tools/test_potions.tscn` (182 Checks). Dev-Button ENTWICKLER -> ALLE TRÄNKE (ALLE STUFEN).
- **Noch nicht:** Lichtfischer fällt nicht eigens auf das Irrlicht herein, Wildtiere meiden es nicht, Quest-Freischaltung der Rezepte.
