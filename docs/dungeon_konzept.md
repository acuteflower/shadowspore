# Shadowspore — Dungeon-System, Steinsetzer-Prüfungstafel, SÜDKAP & Erster Dungeon (Finales Konzept)

> **Status:** **Gebaut & Verifiziert (M1–M7 komplett)** (Stand: 2026-11-24 — alle 13 Design-Entscheidungen umgesetzt, per Headless-Testsuiten & Ingame-Screenshots verifiziert).
> **Baut auf:** der v2-Zonenwelt **ALTMARK** ([v2_zonenwelt_atlas_konzept.md](v2_zonenwelt_atlas_konzept.md)), `PocketSpace` & `ZoneCoop` ([pocket_space.gd](../src/world/pocket_space.gd), [zone_coop.gd](../src/world/v2/zone_coop.gd)), dem Stufen- & Meilensteinsystem ([level_fortschritt_konzept.md](level_fortschritt_konzept.md)), der bestehenden `BossBar` ([boss_bar.gd](../src/ui/boss_bar.gd)), Waffenverfeinerung ([refinement_konzept.md](refinement_konzept.md)), Talismanen ([talisman_konzept.md](talisman_konzept.md)), Magie ([magie_konzept.md](magie_konzept.md)), Beutetruhen ([beutetruhen_konzept.md](beutetruhen_konzept.md)) und `CloudSession` ([cloud_session.gd](../src/autoload/cloud_session.gd)).

---

## 0. Die Vision in einem Absatz

Über die elf Zonen von **ALTMARK** liegen an geografisch und geschichtlich logischen Orten **Dungeons** („Gewölbe & Prüfungen“): versunkene Steinsetzer-Schleusen am **Südkap**, ein gebrochener Brückenkopf in Erlenfurt, Sporenkanäle unter Glimmrast, sturmumtoste Wächterhorste am Klippenstieg bis hin zum Blütensaal von Varnholm. Anders als die offenen Zonen sind Dungeons **an eine Mindeststufe gebunden (`min_level` 5 bis 30)**, **beliebig oft wiederholbar** (allein oder mit **1–4 Spielern im Koop**) und führen **immer eine eigene, handgebaute `.tscn`-Szene** mit unverwechselbarem Thema, eigener Licht-/Klangregie und eigener Spielmechanik. Über die **Schleierresonanz** erhalten Spieler täglich bis zu **4 besondere Hauptbelohnungen** (**2 Echtzeit-Refreshes täglich à +2 Ladungen** um 06:00 & 18:00 UTC plus Lost-Ark-**Ruhebonus**). Flankiert wird das System von einem eigenen, edlen Vollbild-Interface — der **Steinsetzer-Prüfungstafel** (inkl. **`ECHOTAUSCH`**-Reiter & gespeicherten Bestzeiten) — sowie spielweiten Lost-Ark-Kampf-Upgrades (**Klangkonter**, **Taumel-Prüfung** und **mehrstufige Boss-HP-Schichten**). Den Auftakt bildet der vollständige Ausbau von **SÜDKAP (Sturmhafen)** als 2. spielbare Zone (nahtlos ab `WINDKAP` begehbar) inklusive Dungeon #1: **„Die Gezeitenkammern von Sturmhafen“**.

---

## 1. Kern-Säulen (Lost-Ark-DNA in Shadowspore)

| Säule | Festlegung |
|---|---|
| **Immer eine eigene Szene** | Kein generischer Baukasten: Jeder Dungeon ist eine eigenständige Godot-Szene (`res://src/world/dungeons/<id>/<id>.tscn`), gemountet in `PocketSpace.Lane.DUNGEON` innerhalb von `ZoneWorld`. |
| **Vier klare Archetypen** | Abwechslung über ganz ALTMARK: **Schwarm-Tiefe** (`swarm`), **Abgrund-Expedition** (`expedition`), **Sturmfeld** (`arena`) und **Wächter-Jagd** (`guardian`). |
| **Mindeststufe als Fortschrittsziel** | Offene Zonen bleiben stufenfrei; Dungeons geben der Wachstumsranke (`Stufe 1–30`) markante Meilensteine ab Stufe 5. |
| **4× täglich Resonanz, 0× FOMO** | Gemeinsamer 4er-Vorrat, **06:00 & 18:00 UTC je +2 Ladungen**, **Ruhebonus** bei Überlauf, individueller Wahl-Haken vor dem Start (erst beim Sieg abgezogen). |
| **Einheitliche Spannung: 3 Gruppen-Schleierfunken** | In **allen** Dungeons gilt ein geteilter Pool aus exakt **3 Schleierfunken** (`✦ ✦ ✦`) für Respawns — bei `0` Funken und Wipe folgt Boss-Reset bzw. Run-Abbruch. |
| **Spielweiter Lost-Ark-Kampfschliff** | **Klangkonter (Blauer Aufblitz)**, **goldener Taumel-Balken (Stagger Check)** und **mehrstufige Boss-HP-Schichten (`×5` / `×12`)** bereichern Dungeons **und** große Oberwelt-Bosse/Eliten. |
| **Eigenes, ikonisches Interface** | Die **Steinsetzer-Prüfungstafel** (`G` oder am Tor), ein maßgeschneidertes In-Dungeon-HUD und eine **Abschluss-/MVP-Karte** mit Solo- & Koop-Statistiken und Bestzeit-Rekord. |

---

## 2. Die vier Dungeon-Archetypen

| Archetyp (`archetype`) | Vorbild (Lost Ark) | Raumgefühl & Ablauf | Typische Dauer |
|---|---|---|---|
| **I · SCHWARM-TIEFE (`swarm`)** | *Chaos Dungeon* | Enge bis mittelgroße Untergrund-Szenen (Kanäle, Katakomben, Sporenstollen) mit hoher Gegnerdichte, **Läuterungs-Balken (0 → 100 %)** über 2–3 Riss-Abschnitte und aufbrechbaren Sporenkernen. | 4–6 Min. |
| **II · ABGRUND-EXPEDITION (`expedition`)** | *Abyssal / Story Dungeon* | Größere, zusammenhängende Handwerks-Szene mit Erkundung, geheimen Seitenwegen (versteckte Truhe, 1× Schleierfaden), **1–2 Umgebungsmechaniken** (Schleusen, Tragsteine, Spiegel) und einem **leichten bis mittleren End-Fight**. | 7–11 Min. |
| **III · STURMFELD (`arena`)** | *Cube / Kurzan-Front* | Weite, eher **offene Kampffläche** (Brückenkopf, Klippenplateau, Amphitheater) mit 5–7 eskalierenden Wellen und dynamischen Schlachtfeld-Veränderungen (Flut, Blitze, Pylone). | 5–7 Min. |
| **IV · WÄCHTER-JAGD (`guardian`)** | *Guardian / Legion Raid* | Kompakte Jagd- oder Heiligtums-Szene mit kurzem Auftakt, die sich fast komplett um **einen großen, mehrphasigen Bosskampf** mit voller Mechanik-Tiefe dreht. | 4–8 Min. |

---

## 3. Spielweite Lost-Ark-Kampf-Upgrades (Dungeons & Oberwelt-Bosse)

Diese drei Systeme werden sauber als wiederverwendbare Bausteine gebaut und greifen sowohl in Dungeons als auch bei großen Oberwelt-Gegnern (`Leerenbrecher`, `Mornath`, `Morwenna`, `Aurelith`, markierte Nacht-Eliten):

### 3.1 Klangkonter (*Der Blaue Aufblitz* — `CounterComponent`)
- **Ankündigung:** Vor markanten Ansturm-, Sprung- oder Rammangriffen blitzt der Gegner für **`0,45–0,50 s`** hell **Steinsetzer-Eisblau (`#4df2ff`, unlit Shader-Override)** auf, begleitet von einem klaren metallischen Klangstein-Signal.
- **Auslösung:** Trifft ein Spieler-Waffenschlag oder Nahkampf-Zauber innerhalb dieses Fensters in den vorderen **`110°`-Frontkegel** des Gegners, zündet der **Klangkonter**:
  - `110 ms` Hit-Stop (im Solo mit sanftem Kamera-Punch; im Koop ohne `Engine.time_scale` über lokalen Rig-Freeze + Schockring),
  - donnernder Klangstein-Akkord (`counter_hit.wav`) + aufleuchtendes Runen-Echo `KONTER!` (unlit),
  - der Angreifer wird sofort unterbrochen, schlittert zurück und liegt **`2,8 s` betäubt offen** (`+25 %` erlittener Schaden).
- **Synergie mit Ellie:** Mit dem **Schattenschritt (`Alt` / `B`, `0,13 s`)** blinzelt man bei blauem Aufblitzen blitzschnell vor den Boss und landet den Konter. *(Interne Boss-Abklingzeit: `18–25 s` gegen Dauerkontern.)*

### 3.2 Taumel-Prüfung (*Goldener Haltungsbalken* — `StaggerComponent`)
- **Darstellung:** Kanalisiert ein Boss oder Elite eine starke Raum-Attacke, klappt direkt **unter der `BossBar`** ein **gold-violetter Taumel-Balken** auf, während sich am Boden um den Gegner ein Runenring zusammenzieht.
- **Taumel-Gewichte (`stagger` in JSON, strikt an Spielerzahl skaliert):**
  - Normale Schwertschläge 1–3: `10–14` · 4. Schlag *Aufwärtshieb*: `24` · 5. Schlag *Wirbelklinge*: `42`
  - **Voll geladener Wuchtschlag:** `55` *(Hauptwerkzeug für Haltungsbrüche!)*
  - Zauber (*Wurzelgrund*, *Leerenschlund*, *Bannlicht*): `30–45` · Spitzhacke gegen Steinpanzer: `50`
- **Ergebnis:** Leert sich der Balken rechtzeitig, zersplittert die Kanalisierung, der Boss kniet **`4,0 s` `EXPOSED`** nieder (`+30 %` Schaden) und der Kampf-Zähler vermerkt einen **Taumelbruch** für die Endstatistik.

### 3.3 Lost-Ark-Upgrade für `BossBar` (Mehrstufige HP-Schichten + Live-Taumelbalken)
Die bestehende [boss_bar.gd](../src/ui/boss_bar.gd) behält ihren unverwechselbaren Shadowspore-Riss-Look, wird aber um das legendäre Lost-Ark-Gefühl erweitert:
- **Mehrstufige HP-Schichten (`bars: int`, z. B. `×5` bei Vorgath, `×10` bei Mornath, `×15` bei Endgame-Wächtern):**
  - Rechts neben dem Lebensriss steht in gestochen scharfer Gold-Pixelschrift der aktuelle Schichtzähler **`×5` → `×4` → `×3` → `×2` → `×1`**.
  - Jede volle Schicht trägt eine eigene, harmonische Shadowspore-Farbe, die beim Schichtbruch weich zur darunterliegenden Schicht aufreißt (z. B. *Tiefviolett → Leucht-Türkis → Smaragd → Bernstein-Gold → Glut-Magenta* auf der letzten Leiste), inkl. kurzem Riss-Blitz & Schütteln bei jedem Schichtwechsel!
  - Auf der Leiste bleiben feine Bruchmarken für Phasen-Schwellen (z. B. `×3` = `60 %` Taumel-Phase, `×2` = `30 %` Springflut).
- **Integrierte Taumel-Leiste:** Sobald `StaggerComponent` aktiv wird, fährt direkt unter der HP-Leiste der **goldene Taumel-Balken** samt kleinem Hammer-/Bruch-Symbol aus und zerspringt bei Erfolg in Funken.
- **Kein Zusatz-Ballast:** Normale Heilung (Beeren, Kochen, Alchemie-Tränke) bleibt unverändert frei nutzbar; es gibt keine künstlichen Positions-Bodenbögen oder zufälligen Ether-Drops.

---

## 4. Schleierresonanz, 2 Refreshes täglich & Echosplitter-Wirtschaft (`ResonanceRules`)

### 4.1 Die 4 Ladungen, Refresh-Takt & Ruhebonus

| Regel | Exakte Spezifikation |
|---|---|
| **Gemeinsamer Vorrat** | Maximal **4 Ladungen** (`max_charges = 4`) über alle Dungeons hinweg (pro Charakter, portabel über `CloudSession.COOP_PORTABLE_KEYS`). |
| **2 Echtzeit-Refreshes / Tag** | Täglich um **06:00 Uhr UTC** und **18:00 Uhr UTC** (entspricht 07:00 / 19:00 MEZ bzw. 08:00 / 20:00 MESZ) regenerieren **je +2 Ladungen** (`2 × 2 = 4` besondere Belohnungen täglich). |
| **Zeitquelle** | Autoritativ über `CloudSession`-Serverzeitstempel (Nakama) mit lokalem Offline-Fallback `max(Time.get_unix_time_from_system(), last_seen_unix)` gegen Uhr-Zurückstellen. |
| **Ruhebonus (*Ruhende Glut*)** | Steht das Konto bei einem Refresh bereits auf `4/4`, wandern überlaufende Ladungen in **Ruhebonus-Halbpunkte** (`rest_units`, Cap `8` = `4` volle Bonus-Stufen). Je **2 verfallene Ladungen = 1 volle Ruhebonus-Stufe**, die beim nächsten Resonanz-Sieg automatisch mitverbraucht wird und das **Resonanz-Reliquiar verdoppelt**! |
| **Individueller Wahl-Haken** | Vor jedem Start entscheidet jeder Spieler für sich selbst: `☑ SCHLEIERRESONANZ EINLÖSEN (1/4)`. Der Verbrauch erfolgt **erst beim Sieg** (niemals beim Betreten, Wipe oder Abbruch). |

### 4.2 Die drei Beute-Ebenen & der `ECHOTAUSCH`
1. **Resonanz-Reliquiar (*Mit Haken = 1 Ladung*, bis zu 4× täglich):**
   - Spezielle türkis-goldene Dungeon-Truhe (`LootChest`-Variante), die beim Sieg in einer Lichtsäule erscheint — jeder Teilnehmer mit aktivem Haken bekommt seinen eigenen Wurf (mit Ruhebonus doppelt!).
   - Inhalt: garantierte **Verfeinerungsmaterialien** nach Dungeon-Stufe (Eisenbarren/Platten/Leerensplitter früh → Schattenkerne/Leerenschlacke spät), **ungeschliffene Zauberkristalle/Steine**, kräftige XP (`source = "dungeon"`), Kupfer sowie Chance auf die **Dungeon-Exklusivbeute** (Talismane, Waffen, Rezepte).
2. **Wiederholungs-Truhe (*Ohne Haken = 0 Ladungen*, unbegrenzt oft spielbar):**
   - Kleine Steinsetzer-Truhe mit moderatem Kupfer, Verbrauchsmaterial und **Echosplittern** (Dungeon-Währung, **Wochencap: 120 Stück**, Reset jeden Montag `06:00 UTC`).
3. **Einmalige Erstläuterungs-Kiste (*First Clear*):**
   - Beim allerersten Abschluss eines Dungeons gratis obendrauf (verbraucht keine Resonanz-Ladung!): hohe Einmal-XP, garantiertes Signatur-Stück des Dungeons und Chronik-Eintrag im `AtlasBook`.
4. **Direkter `ECHOTAUSCH`-Reiter in der Prüfungstafel:**
   - Weil Glimmrast/Torben in ALTMARK noch hinter gesperrten Zonen liegen, lösen Spieler ihre **Echosplitter** sofort im zweiten Reiter der **Steinsetzer-Prüfungstafel** ein:
     - **Pechschutz (Pity)** für Dungeon-Exklusivbeute (z. B. *Klinge der Hafenwache* & *Gezeitenreif*, freigeschaltet nach Erstläuterung des jeweiligen Dungeons),
     - wöchentlich begrenzte Pakete aus Eisenbarren, Eisenplatten, Leerensplittern, rohen Küstensteinen & Trankzutaten.

---

## 5. Das eigene Dungeon-Interface (Vollständiges UI-Konzept)

Das Dungeon-System erhält eine eigene, unverwechselbare visuelle Identität innerhalb von Shadowspores `640×360`-Pixelkunst-Sprache: **Steinsetzer-Schiefer & Klangstein-Türkis (`#4df2e0`) kombiniert mit Ranken-Gold (`#ffd98a`) und dem animierten Schattenschleier (`map_veil.gdshaderinc`)**.

### 5.1 Die Steinsetzer-Prüfungstafel (`DungeonWindow` — Taste `G` oder `E` am Tor)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [ PRÜFUNGEN ]  [ ECHOTAUSCH (38 ◈) ]      [✦][✦][✦][✧] 3/4 · +2 IN 04:18    │
│                                            RUHENDE GLUT [████░░░░] 1× 2x     │
├──────────────────────────┬───────────────────────────────────────────────────┤
│  ALTMARK · GEWÖLBE       │ ┌───────────────────────────────────────────────┐ │
│ ──────────────────────── │ │  [GEMALTES SZENEN-BANNER: GEZEITENKAMMERN]    │ │
│ ▸ [II] GEZEITENKAMMERN   │ │  DIE GEZEITENKAMMERN VON STURMHAFEN           │ │
│    SÜDKAP · STUFE 5  ✓   │ │  ABGRUND-EXPEDITION · AB STUFE 5 · 1–4 SP.    │ │
│ ──────────────────────── │ └───────────────────────────────────────────────┘ │
│   [III] ???              │  BESTZEIT: 06:14  ·  SIEGE: 3  ·  ERSTLÄUTERUNG ✓ │
│    ERLENFURT · STUFE 8   │                                                   │
│ ──────────────────────── │  BEUTE-VORSCHAU:                                  │
│   [I]  ???               │   [Reliquiar] [Barren] [Splitter] [Anker] [Klinge]│
│    GLIMMRAST · STUFE 11  │                                                   │
│ ──────────────────────── │  ☑ SCHLEIERRESONANZ EINLÖSEN (1/4 · 2× GLUT!)     │
│   [IV] ???               │                                                   │
│    KLIPPENSTIEG · ST. 14 │  ┌───────────────────┐  ┌───────────────────────┐ │
│                          │  │  ALLEIN BETRETEN  │  │ GRUPPE RUFEN (1–4)    │ │
│  (Scrollbare Liste)      │  └───────────────────┘  └───────────────────────┘ │
└──────────────────────────┴───────────────────────────────────────────────────┘
```

- **Zwei klare Kontexte derselben Tafel:**
  1. **Am physischen Dungeon-Tor (`E`):** Öffnet die Tafel direkt vorgewählt auf genau diesem Dungeon. Unten sind **`ALLEIN BETRETEN`** und **`GRUPPE RUFEN (KOOP)`** aktiv (sofern `ProgressComponent.level >= min_level`; sonst klar rot versiegelt: `BENÖTIGT STUFE 5`).
  2. **Unterwegs per Taste `G` (globale Übersicht):** Zeigt alle entdeckten Dungeons (plus schattenverhüllte Silhouetten kommender Dungeons mit Zone & Mindeststufe als Motivation!), Bestzeiten, die 4 Resonanz-Siegel, Refresh-Countdown, Ruhebonus und den vollen **`ECHOTAUSCH`**-Reiter. Statt `ALLEIN BETRETEN` steht unten der Knopf **`WEG ZEIGEN / WEGSTEIN`** — ein Klick schwenkt in den Atlas zur Route Richtung Tor bzw. springt zum nächsten erweckten Wegstein der Zone (z. B. *Wächterin von Sturmhafen*)! *(Später schaltet eine gebaute Steinsetzer-Stele in Glimmrast auch den Direktstart aus der Heimatstadt frei.)*
- **Reiter `ECHOTAUSCH`:** Zeigt das eigene Echosplitter-Guthaben (`◈`), den Wochen-Fortschritt (`38 / 120`), und links/rechts klar gegliederte Tausch-Karten mit Wochenlimits, Gegenstands-Tooltips (`ItemTooltip`) und sofortigem Host-autoritativen Kauf.

### 5.2 Der Koop-Sammelruf (`DungeonReadyBanner`)
- Startet ein Spieler am Tor **`GRUPPE RUFEN`**, prüft der Host alle verbundenen Mitspieler auf `level >= min_level` (wer das Mindestlevel nicht erfüllt, wird im Tor-Fenster namentlich genannt, damit die Gruppe Bescheid weiß).
- Alle berechtigten Mitspieler (auch in anderen Zonen!) erhalten oben mittig das kompakte **Sammelruf-Banner** (20 s Countdown, dezenter Klangstein-Ruf):
  - Zeigt Dungeon-Name, Archetyp, 4 farbige Spieler-Rauten (`P1..P4` mit Live-Häkchen `✓` / `?`), den **eigenen** Resonanz-Haken (`☑ Resonanz einlösen`) und die Knöpfe **`ANNEHMEN`** / **`ABLEHNEN`**.
  - Sobald alle berechtigten Teilnehmer annehmen, schließt der dunkle Gezeiten-/Schleier-Wipe (`dungeon_wipe.gdshader`) und zieht die Gruppe gemeinsam in die Dungeon-Szene.

### 5.3 Das Live-HUD im Dungeon (`DungeonHud`)
Sobald man in einer Dungeon-Szene steht, schaltet das HUD sauber in den **Dungeon-Modus** (Uhr/Wetter der Außenwelt pausieren optisch; normale Quest-Ranke weicht der Dungeon-Aufgabe):
- **Oben links:** Kompakte Schiefer-Plakette mit **Live-Laufzeit (`03:42`)** und den **3 geteilten Gruppen-Schleierfunken (`✦ ✦ ✦`)** — jeder verlorene Funke erlischt mit kurzem Riss-Effekt.
- **Oben rechts:** Klares **Abschnittsziel** (z. B. *„Kappe die Sporenstränge an der West-Flutglocke (2/3)“* oder in `swarm`-Dungeons der **Läuterungs-Balken `64 %`**).
- **Oben mittig:** Die aufgewertete **Multi-Bar `BossBar`** (`×5` Schichten + ausfahrbarer goldener **Taumel-Balken**).
- **Links (im Koop):** Die bestehende `CompanionVine` zeigt die Gruppenmitglieder mit HP-Balken & „GEFALLENER“-Status.

### 5.4 Die Abschluss- & Statistik-Karte (`DungeonResultWindow`)
Nach dem finalen Treffer (kurze dramatische Zeitlupe im Solo / Hit-Stop-Blitz im Koop) landet das **Resonanz-Reliquiar** in der Arena, und nach `2,5 s` (oder per `E` am Abschluss-Siegel) präsentiert sich die **Abschluss- & MVP-Karte**:
- **Kopf:** `GEWÖLBE GELÄUTERT` · Clear-Zeit (`06:14`) + goldenes **`NEUE BESTZEIT!`**-Siegel, falls der gespeicherte Rekord unterboten wurde.
- **Kampfstatistik (Solo UND Koop!):**
  - Gesamtschaden (`DPS` / `%`-Anteil im Koop),
  - gelandete **Klangkonter**,
  - ausgelöste **Taumelbrüche**,
  - erlittene Treffer & verbrauchte Schleierfunken.
  - *Im Koop (2–4P):* 1–2 Ehrenplaketten pro Spieler (*SCHICKSALSKLINGE*, *KLANGBRECHER*, *ERSCHÜTTERER*, *UNBERÜHRT*).
- **Beute-Übersicht** (Erstläuterung / Resonanz-Reliquiar / Ruhebonus `×2` / Echosplitter) sowie unten zwei Knöpfe: **`NOCH EINMAL`** (direkter Neustart / neuer Sammelruf) und **`ZURÜCK NACH SÜDKAP`**. *(Die Karte lässt sich auch kurz wegklappen, um das Reliquiar und die Arena noch in Ruhe zu betrachten und durch das Ausgangsportal zu gehen.)*

---

## 6. Technische Architektur: Eigene `.tscn`-Szene in `PocketSpace.Lane.DUNGEON`

Jeder Dungeon führt **immer eine eigene `.tscn`-Szene** (`res://src/world/dungeons/<id>/<id>.tscn`, Root-Skript `extends DungeonScene`), bleibt aber vollständig kompatibel mit `ZoneWorld` und Koop Option B:

```
ZoneWorld (offene Welt & Netzwerk bleiben permanent aktiv)
 └─ DungeonManager (Node2D, Gruppe "dungeons", Host-autoritativ)
     ├─ Slot 0 [-80000, -112000] ──► Instanz suedkap_gezeitenkammern.tscn (8192×8192 px)
     ├─ Slot 1 [-71808, -112000] ──► (frei für parallele Solo-/Koop-Instanz)
     ├─ Slot 2 [-63616, -112000] ──► (frei)
     └─ Slot 3 [-55424, -112000] ──► (frei)
```

- **`PocketSpace.Lane.DUNGEON`:** 4 feste Slots à `8192 × 8192 px` (`512 × 512` Tiles) bei `DUNGEON_ORIGIN = Vector2(-80000.0, -112000.0)` — strikt im negativen Quadranten unter `LIMIT = -16000.0`, ohne jede Überschneidung mit `ROOM` oder `LARGE`.
- **Automatische Netzwerk-Sichtbarkeit:** `ZoneCoop._evaluate_entity_visibility()` prüft bereits `PocketSpace.locate(pos)` — Gegner, Projektile, Bosse, Truhen und Drops innerhalb eines Dungeon-Slots werden automatisch **nur** an Peers repliziert, die in genau diesem Slot stehen!
- **Rückkehr & Entladen:** Der Host merkt sich pro Teilnehmer `{return_pos, return_zone, use_resonance}`. Bei Tod und `>0` Schleierfunken respawnt der Spieler nach `3 s` am letzten Raum-Checkpoint der Instanz und zieht `1` Funken ab; bei `0` Funken & Wipe aller lebenden Teilnehmer erscheint die Wipe-Karte (`ERNEUT VERSUCHEN` vom letzten Boss-Checkpoint oder `VERLASSEN`). Sobald der letzte Teilnehmer den Slot verlässt, werden alle gespawnten Gegner/Drops abgeräumt und die `.tscn`-Instanz per `queue_free()` vollständig freigegeben.
- **Beleuchtung & Terrain:** `DayNight` fragt `DungeonManager.ambient_color()` ab (genau wie `MineManager`); `Terrain.patches` fragt `DungeonScene.surface_at(pos)` ab (nasser Quaderstein, Holzsteg, knietiefes Gezeitenwasser); `NightLight`s laufen über `DungeonManager.night_at(node, amount) -> 1.0`, sodass alle Lichter & Glow-Sheets im Gewölbe stets strahlen.
- **Entwickler-Direktstart:** CLI `--dungeon=suedkap_gezeitenkammern` und Pausemenü `ENTWICKLER → DUNGEON` für sekundenschnelle Iterationen und automatisierte Tests.

---

## 7. Einbau von `SÜDKAP` (Sturmhafen) als 2. vollwertige spielbare Zone

Um den ersten Dungeon organisch in die Welt einzubetten, wird **`suedkap`** ([data/world/zones/suedkap/zone.json](../data/world/zones/suedkap/zone.json), `513 × 402` Tiles, Class XL, alter Name **`STURMHAFEN`**) nach demselben Qualitätsstandard wie `WINDKAP` ausgebaut:

### 7.1 Nahtloser Übergang von `WINDKAP`
- **Schwelle `windkap_suedkap` ab sofort offen:** Der bisherige `bramble_wall`-Blocker in [thresholds_main.json](../data/world/thresholds_main.json) und [windkap/zone.json](../data/world/zones/windkap/zone.json) wird entfernt. Man spaziert von `WINDKAP` über die alte Steinbogenbrücke und die gepflasterte Küsten-Karrenstraße (`seed: 502`) **ohne Schnitt und ohne Ladebildschirm** direkt hinüber ins `SÜDKAP`!
- Die drei weiterführenden Binnenland-Schwellen von `SÜDKAP` (`suedkap_erlenfurt`, `suedkap_glimmrast`, `suedkap_hexenwald_kern`) erhalten physische Blocker + `closed_reason`-Hinweise, solange diese Zonen noch Platzhalter sind.

### 7.2 Identitäts-Checkliste & 6 benannte Orte im `SÜDKAP`

| Ort (`places`) | Lage in `suedkap` | Stimmung & Inhalt |
|---|---|---|
| **1. Der Küstenpfad** | Westen (Übergang ab `windkap_suedkap`) | Windgebeugte Eichen, alte Steinsetzer-Meilensteine entlang der Karrenstraße, Blick auf die weite Südbucht. |
| **2. Der Treibholzstrand** | Südwestküste | Flacher Sand-/Kiesstrand mit gestrandeten Planken, frei besichwimmbarer Brandung (`REGIME_SURF`), Muschel-/Salzflora und erstem Küstenrätsel (*Irrlichtspur*). |
| **3. Die Salzklippen** | Südliche Landzunge (Höhenzug) | Felsige Aussichts-Platte mit **`VistaPoint` („Sturmkanzel“)** — weiter Kamerazug über die zerbrochenen Molen, das offene Meer und die fernen Schären! |
| **4. Der Wächterplatz von Sturmhafen** | Zentrum (an der Straßenkreuzung vor dem Hafen) | Erweckbarer Wegstein **`waechterin_sturmhafen` („Wächterin von Sturmhafen“)** — schaltet Schnellreise zwischen `WINDKAP` und `SÜDKAP` frei und dient als Respawn-Wahl! |
| **5. Die Zerbrochenen Lagerhäuser** | Nordosten (hinter dem Hafen) | Verwitterte Steinsetzer-Grundmauern, altes Pflaster, ein zweites Rätsel (*Krähenschatz*) und eine bewachte seltene Mondsiegeltruhe. |
| **6. Die Alte Mole von Sturmhafen** *(Leuchtturm-Landmarke)* | Südost-Landzunge am Wasser | Zyklopischer Steinsetzer-Wellenbrecher mit zwei verwitterten Leuchtfeuersäulen, herabführender salznasser Steintreppe und dem **Fluttor zu „Die Gezeitenkammern“ (`DungeonEntrance`)**! |

- **Erschließung & Leben:**
  - **8 handgesetzte Schleierfäden** (`VeilThreads`) für die `SÜDKAP`-Seite im `AtlasBook` (mit eigenen 30 % / 60 % / 100 %-Kosmetikbelohnungen: Kartenstempel *„STURMHAFEN-ANKER“*, *Meeresgischt-Rahmenranke*, Titel *„GEZEITENWANDERIN“*).
  - **2 Truhen + 2 Rätsel** (Irrlichtspur & Krähenschatz).
  - **Küsten-Flora & -Fauna:** Beerenbüsche, Sonnenblüten, Funkenmohn, Rohrkolben, Bachminze, Möwen/Krähen/Kaninchen/Füchse/Otter/Reiher.
  - **Nacht-Gefahrengrad `RAU` (+20 %):** Spürbare Steigerung gegenüber dem ruhigen `WINDKAP` — nachts steigen **`shadow_spider`**, erstmals **`void_listener`** (Leerenhorcher) und an den Buchten **`light_fisher`** auf! Damit ist das Hochleveln auf **Stufe 5** direkt in `WINDKAP` + `SÜDKAP` organisch und spannend.
  - **Kartenbake:** Neu-Bake von `suedkap/baked/{map,map_light,far}.png` (`4 px/Tile`) via `tools/paint_zone_map.py`, sodass Mole, Wege und Dungeon-Vorplatz im Atlas gestochen scharf gezeichnet sind.

---

## 8. Vollständige Detailplanung — Dungeon #1: „DIE GEZEITENKAMMERN VON STURMHAFEN“

### 8.1 Steckbrief
- **ID:** `suedkap_gezeitenkammern`
- **Eigene Szene:** `res://src/world/dungeons/suedkap_gezeitenkammern/suedkap_gezeitenkammern.tscn`
- **Archetyp:** **II — Abgrund-Expedition** (`expedition`)
- **Mindeststufe:** **Stufe 5** (passt punktgenau zum 1. Meilenstein: 1. Talisman-Platz + 4. Kombo-Schlag *Aufwärtshieb*)
- **Größe:** `148 × 116 Tiles` (`2368 × 1856 px`, handgebaut in `PocketSpace.Lane.DUNGEON`)
- **Spielzeit:** ~8–11 Min. (Ersterkundung) · ~5–6 Min. (Daily-Run) · **3 Gruppen-Schleierfunken** (`✦ ✦ ✦`)

### 8.2 Atmosphäre, Palette & eigene Szenen-Technik
- **Optik:** Nasses Schieferblau-Mauerwerk der Steinsetzer (`#1d2738`–`#49607a`) mit Salzkrusten, dunkle Eichenholz-Stege und gestrandete Schiffsspanten (`#2b1e26`), korrodierte Bronze-Schleusenräder (`#4d7a6e`), biolumineszente Seepocken & Klangstein-Rinnen in kühlem Türkis (`#4df2e0`, unlit) im harten Kontrast zum Sporen-Magenta (`#ff4fd8`).
- **Licht & Shader:** Drei schräge Küstenlicht-Schächte durch geborstene Gewölbedecken; eigener **`tide_water.gdshader`** für die Flutbecken, dessen sichtbarer Wasserstand (`tide_level`: `1.0` → `0.5` → `0.0`) sich live absenkt, wenn die Flutglocke geläutet wird!
- **Klangkulisse (`tools/audio_dungeon_suedkap.py`):** Dumpfe Ozean-Brandung hinter den Seemauern, Salzwasser-Tropfen, knarzende Holzstege, tiefer Klangstein-Glockenhall, ratternde Bronze-Winden, Konter-Gong und Springflut-Rauschen.

### 8.3 Die 4 Abschnitte (Handgebautes Layout)

```
                      [GEHEIME SCHMUGGLERNISCHE]
                      (1× Bonus-Schleierfaden + Kiste)
                                 │ (zerschlagbare Bretterwand)
  ┌──────────────────┐    ┌──────┴───────────────┐
  │ 1. GEBROCHENE    │    │ 2. WESTLICHES        │
  │    EINFAHRT      ├───►│    WRACKBECKEN       │
  │ (Start + Blick   │    │ (Stege, Lichtfischer,│
  │  aufs Fluttor)   │    │  West-Flutglocke 🔔) │
  └──────────────────┘    └──────────┬───────────┘
                                     │ (Wasserpegel sinkt live!)
                                     ▼
                          ┌──────────────────────┐
                          │ 3. ALTER KRANHOF &   │
                          │    TROCKENDOCK       │
                          │ (Schiffsspanten,     │
                          │  Dock-Brecher,       │
                          │  Klangstein-Winde ⚙️)│
                          └──────────┬───────────┘
                                     │ (Fluttor öffnet + Rastfeuer 🔥)
                                     ▼
                       ╔════════════════════════════╗
                       ║ 4. DAS GROSSE SCHLEUSEN-   ║
                       ║    BECKEN (BOSS-ARENA)     ║
                       ║    [Seetor / Brandung]     ║
                       ║   [Poller]  [Poller]       ║
                       ║        ★ VORGATH ★         ║
                       ║          [Poller]          ║
                       ║  (Reliquiar + Rückkehr)    ║
                       ╚════════════════════════════╝
```

1. **Abschnitt 1 — Die Gebrochene Einfahrt *(Auftakt & visuelles Ziel)*:**
   - Abstieg über nasse Stufen mit feierlicher Titel-Einblendung (`DIE GEZEITENKAMMERN · Altes Schleusenwerk von Sturmhafen`).
   - Direkt voraus eine Brüstung mit Blick auf das noch überflutete Haupt-Schleusentor (sofortiges Verständnis ohne Textwand).
   - Auftakt-Gefecht gegen `4 Schattenspinnen` zwischen geborstenen Fässern.
2. **Abschnitt 2 — Das Westliche Wrackbecken *(Erkundung, Lichtfischer & Flutglocke)*:**
   - Knarzende Stege über knietiefem Beckenwasser und das Wrack eines alten Küstenseglers.
   - `2 Leerenhorcher` sichern die Stege; im Beckenwasser dazwischen lauern **`2 Lichtfischer`** mit ihren falschen Hafenlaternen.
   - **Geheimnis Nordwest:** Hinter zerschlagbaren morschen Planken liegt die *Schmugglernische* mit einer **Wurzelkiste** (jeden Run) und einem einmaligen **Schleierfaden**.
   - **Mechanik I (West-Flutglocke):** `3` pulsierende Sporenstränge kappen (löst einen kurzen Hinterhalt aus `3 Spinnen` + `1 Elite-Spinne` aus), dann die große Klangglocke anschlagen (`E` oder schwerer Hieb) → tiefer Hall durchs ganze Gewölbe, der Wasserpegel sinkt live ab und legt die Treppe ins Trockendock frei!
3. **Abschnitt 3 — Der Alte Kranhof & Trockendock *(Brecher & Klangstein-Gegengewicht)*:**
   - Trockengelegtes Dock mit riesigen Eichenspanten und einem alten Hafenkran.
   - **Gefecht:** Ein **`Leerenbrecher` (*Dock-Zermalmer*)** + `2 Spinnen` (lässt sich mit seinem Rammstoß herrlich gegen die Schiffsspanten locken!).
   - **Mechanik II (Klangstein-Winde):** Das leuchtende **Klangstein-Gegengewicht** über das bestehende Tragesystem (`Player.start_carry`) 20 Tiles weit zur Ost-Winde tragen (im Koop schirmen Mitspieler den Träger gegen `4` nachrückende Spinnen ab; Solo nur `1` faire, langsame Spinne). Das Haupt-Fluttor knirscht auf.
   - **Checkpoint & Rastschale:** Direkt vor der Arena brennt eine Steinsetzer-Feuerschale (speichert den Respawn-Punkt für die 3 Schleierfunken und heilt einmalig `40 %` HP + volle Ausdauer).
4. **Abschnitt 4 — Das Große Schleusenbecken: Endboss **VORGATH, BRUT DER MOLE** (`×5` HP-Schichten):**
   - Runde Steinsetzer-Arena (`340 × 250 px`) mit dem rissigen Nord-Seetor (schäumende Brandung dahinter) und **3 massiven Steinpollern** im Dreieck.
   - **Vorgath (`~440 HP` Solo, Koop skaliert `1,65× / 2,25× / 2,80×`, `×5` HP-Balken-Schichten):** Massiges, salzverkrustetes Schattenwesen mit abgerissener eiserner Ankerkette als Schlagarm und einer glimmenden **Messing-Hafenlaterne** auf dem Rücken (*optionale Bruchstelle*).
   - **Moveset (Einsteigerfreundlicher Lost-Ark-Showcase):**
     1. *Kettenfeger:* `135°`-Frontbogen (`0,55 s` klarer Bodentelegraph).
     2. *Brackwasser-Spucke:* `2` (Koop `3`) langsame Salz-Sporenblasen, lassen kurzlebige (`6 s`) verlangsamende Pfützen zurück.
     3. ***Rammflut* (Blauer Klangkonter!):** Blitzt `0,50 s` **eisblau (`#4df2ff`)** auf + Klangstein-Gong (beim allerersten Kontakt kurzer `HintCard`-Tipp *„BLAUER BLITZ: VON VORN KONTERN!“*). Front-Treffer kontert ihn für `2,8 s` zu Boden; alternativ ausweichen und gegen einen Poller krachen lassen (`1,2 s` Taumel).
     4. ***Sog des Tiefendocks* (Taumel-Prüfung bei `60 %` / Schicht `×3`):** Anker in die Mitte, sanfter Sog, `3,8 s` **goldener Taumel-Balken** unter der `BossBar` (Solo mit `1` Wuchtschlag + `1` Kombo sauber brechbar → `4,0 s` `EXPOSED`!).
     5. ***Die Springflut* (Signatur-Mechanik bei `30 %` / Schicht `×2`):** Das Nord-Seetor ächzt; `2,2 s` Vorwarnung mit türkisfarbenen Strömungspfeilen und hell aufleuchtendem Strömungsschatten hinter den **3 Steinpollern**. Die Schaumwalze rauscht hindurch: hinter dem Poller `0` Schaden, und alle Schattenpfützen werden weggewaschen!
     6. ***Bruchstelle Hafenlaterne* (Optional):** Schwere Treffer auf den Rücken reißen die Laterne ab (`part_broken`) → Brackwasser-Blasen erzeugen keine Pfützen mehr + garantiert `+1 Roher Seeglimmer` extra beim Sieg!

### 8.4 Exklusiv-Beute & Echotausch für Sturmhafen (Stufe 5)

| Gegenstand | Art & Seltenheit | Werte / Wirkung | Herkunft |
|---|---|---|---|
| **Ankertropfen von Sturmhafen** | Talisman (`necklace`, ungewöhnlich) | `+18 Leben`, `+3 Rüstung`, `+25 % Rückstoßwiderstand` | **Garantiert** in der Erstläuterungs-Kiste (sofort passend für Talisman-Slot 1 auf Stufe 5!) + Resonanz-Pool |
| **Gezeitenreif** | Talisman (`bracelet`, selten) | `+6 % Schaden`; nach einem **Klangkonter** oder **Schattenschritt** `+16 %` auf den nächsten Treffer (`4 s`) | Resonanz-Reliquiar (`18 %`) oder **Echotausch** (`40 Echosplitter`, ab Erstläuterung) |
| **Klinge der Hafenwache** | Einhandschwert (`rare`, verfeinerbar bis `+15`) | Basis-Schaden `9,5`, korallen-/bronzegeätzter Parierbügel | Resonanz-Reliquiar (`12 %`) oder **Echotausch** (`55 Echosplitter`, ab Erstläuterung) |
| **Resonanz-Reliquiar (Lv. 5)** | Tägliche Hauptbelohnung (1/4, ×2 mit Ruhebonus) | `3–5 Eisenbarren`, `1–2 Eisenplatten`, `1–3 Leerensplitter`, `1 Roher Seeglimmer`, `50–75 Kupfer`, `140 XP` + Chance auf Exklusivbeute | Bei Sieg mit aktivem Haken `☑ Resonanz einlösen` |
| **Wiederholungs-Truhe (0 Ladungen)** | Beliebig oft | `12–18 Echosplitter` (Wochencap `120`), `15–25 Kupfer`, Kräuter/Trankzutaten | Bei jedem Sieg ohne Resonanz-Ladung |

---

## 9. Gesamt-Weltverteilung auf ALTMARK (Ausblick Stufe 5 → 30)

| # | Zone | Stufe | Archetyp | Geplanter Dungeon |
|---|---|---|---|---|
| **1** | **`suedkap`** *(Sturmhafen)* | **5** | `expedition` | **Die Gezeitenkammern von Sturmhafen** *(dieser Meilenstein!)* |
| **2** | **`erlenfurt`** | **8** | `arena` | **Der Gebrochene Brückenkopf** *(offenes Fluss-Sturmfeld)* |
| **3** | **`glimmrast`** | **11** | `swarm` | **Die Sporenkanäle** *(Untergrund-Schwarmgewölbe)* |
| **4** | **`klippenstieg`** | **14** | `guardian` | **Die Nebelkanzel** *(reiner Fjord-Bosskampf)* |
| **5** | **`hexenwald_saum`** | **17** | `expedition` | **Das Versunkene Spiegelkloster** *(Erkundung & Zirkel-Hüter)* |
| **6** | **`hallgrat`** | **20** | `swarm` | **Das Verlorene Westviertel** *(dichtes Ruinen-Schwarmgewölbe)* |
| **7** | **`hexenwald_kern`** | **23** | `guardian` | **Das Wurzelherz am Bleichen Teich** *(großer Bosskampf)* |
| **8** | **`kristallgrat`** | **26** | `arena` | **Das Resonanz-Amphitheater** *(offene Klangkristall-Arena)* |
| **9** | **`muehlenaue`** | **28** | `expedition` | **Die Gruft der Rotmäntel** *(Ordens-Katakomben)* |
| **10** | **`varnholm`** | **30** | `guardian` | **Der Blütensaal** *(Endgame-Spitzenkampf am Großen Riss)* |

---

## 10. Entscheidungsprotokoll (Alle 13 Entscheidungen vom 2026-11-24)

| # | Thema | Verbindliche Entscheidung |
|---|---|---|
| 1 | Zeitbasis & Refresh | **Echtzeit-Takt:** `06:00` & `18:00` UTC je `+2` Ladungen bis Cap `4` + **Lost-Ark-Ruhebonus** bei Überlauf. |
| 2 | Verbrauch & Wiederholung | Gemeinsamer 4er-Vorrat mit **Wahl-Haken** vor dem Start (erst bei Sieg abgezogen); ohne Ladung Basis-Beute + **Echosplitter** (Wochencap `120`); **Erstläuterung** gratis obendrauf. |
| 3 | Zugang & Koop | Erstentdeckung immer physisch am Tor; danach globale Übersicht per Taste `G` & **Koop-Sammelruf** vom Tor aus in alle Zonen. |
| 4 | Tod & Wiederbelebung | Einheitlich in allen Dungeons: exakt **3 geteilte Gruppen-Schleierfunken** (`✦ ✦ ✦`). |
| 5 | Lost-Ark-Kampf-Upgrades | **Klangkonter (Blauer Aufblitz)** + **goldener Taumel-Balken** (Dungeons & große Oberwelt-Bosse/Eliten) + **mehrstufige Boss-HP-Schichten (`×5`/`×12`)** an der `BossBar`. *(Ohne Positionsbogen, ohne Heiltrank-Deckel, ohne Zufalls-Äther/Schicksalsglut.)* |
| 6 | Eigenes Dungeon-Interface | **Steinsetzer-Prüfungstafel** (`DungeonWindow`, eigenes Vollbild-UI mit Schleier-Übergang, Szenen-Banner, 4 Resonanz-Siegeln, Ruhebonus, Beute-Vorschau, Solo/Koop-Start). |
| 7 | In-Dungeon-HUD & Endkarte | Volles Paket: Laufzeit, 3 Schleierfunken, Abschnittsziel, Multi-Bar-`BossBar` + **Abschluss-/MVP-Karte inkl. Solo- & Koop-Kampfstatistik & gespeichertem Bestzeit-Rekord**. |
| 8 | Ausbau von `SÜDKAP` | **Vollwertige 2. spielbare Zone** (wie `WINDKAP`: 6 Orte, Wegstein, Vista, 8 Schleierfäden, 2 Rätsel/Truhen, Küsten-Flora/Fauna, `RAU`-Nächte, geblockte Nachbarschwellen). |
| 9 | Übergang `WINDKAP → SÜDKAP` | **Sofort nahtlos offen** (kein Dornenwall mehr an `windkap_suedkap`). |
| 10 | Dungeon #1 Grundform | **„Die Gezeitenkammern von Sturmhafen“** · Archetyp II (*Abgrund-Expedition*, 4 Abschnitte) · **Mindeststufe 5**. |
| 11 | Endboss *Vorgath* | Einsteigerfreundlicher Lost-Ark-Showcase (`×5` HP-Schichten): Blauer Konter + Ersthinweis, Taumel-Prüfung bei `60 %`, Springflut hinter 3 Steinpollern bei `30 %` + optionale Bruchstelle *Hafenlaterne*. |
| 12 | Echosplitter-Einlösung | Eigener Reiter **`ECHOTAUSCH`** direkt in der Steinsetzer-Prüfungstafel (sofort nutzbar inkl. Pechschutz für *Klinge der Hafenwache* & *Gezeitenreif*). |
| 13 | Taste `G` aus der Ferne | Zeigt alle Infos, Bestzeiten, Ladungen & Echotausch; Knopf führt als **`WEG ZEIGEN / WEGSTEIN`** zum physischen Tor (Direktstart am Tor bzw. später Stadt-Stele). |

---

## 11. Umsetzungsplan (Meilensteine M1 → M7)

| Meilenstein | Inhalt & Dateien | Verifikation |
|---|---|---|
| **M1 · Kernregeln, PocketSpace & Saves** | `PocketSpace.Lane.DUNGEON` (`4×8192 px`), `data/dungeons.json`, `data/dungeon_resonance.json`, pure `ResonanceRules` (06:00/18:00 UTC + Ruhebonus) & `DungeonRules` (Stufe, Skalierung, Echotausch), `SaveGame` + `CloudSession.COOP_PORTABLE_KEYS` (`dungeon_resonance`, `dungeon_stats`, `dungeons_cleared`, `echo_shards`). | `tools/test_dungeon_rules.tscn` (headless) |
| **M2 · Lost-Ark-Kampfbausteine & BossBar v2** | `CounterComponent` (Blauer Aufblitz + Frontkegel + Hit-Stop + Klang), `StaggerComponent` (Taumel-Gewichte & Bruch), Upgrade der [boss_bar.gd](../src/ui/boss_bar.gd) um mehrstufige HP-Schichten (`×N`) & integrierten goldenen Taumel-Balken + Einbindung bei `Leerenbrecher` / `Mornath`. | `tools/test_dungeon_combat.tscn` & `tools/preview_boss_bar_v2.tscn` |
| **M3 · DungeonManager, Tor & Koop-Sammelruf** | `DungeonManager` (Slot-Laden/Entladen eigener `.tscn`-Szenen, 3 Gruppen-Schleierfunken, Kampfstatistik-Tracker), `DungeonScene`-Basisklasse, `DungeonEntrance` + `MapMarkers`-Anbieter, `DungeonReadyBanner`, `dungeon_wipe.gdshader`. | `tools/test_dungeon_coop.tscn` (2-Prozess-Koop-Test) |
| **M4 · Steinsetzer-Prüfungstafel & Dungeon-HUD** | `DungeonWindow` (Vollbild-Interface `G` & Tor-Kontext, Reiter `PRÜFUNGEN` + `ECHOTAUSCH`, 4 Resonanz-Siegel, Ruhebonus, Bestzeiten, `WEG ZEIGEN / WEGSTEIN`), `DungeonHud`, `DungeonResultWindow` (Solo-/Koop-Statistik & MVP), Input-Action `dungeons` (`G`). | `tools/preview_dungeon_ui.tscn` & `tools/test_dungeon_ui.tscn` |
| **M5 · Vollwertige Zone `SÜDKAP` (Sturmhafen)** | Öffnung von `windkap_suedkap` in `thresholds_main.json` & `windkap/zone.json`, vollständiger Ausbau von `data/world/zones/suedkap/zone.json` (6 Orte, Wegstein `waechterin_sturmhafen`, Vista, 8 Schleierfäden, 2 Rätsel/Truhen, Flora/Fauna, `RAU`-Nächte, Nachbar-Blocker), `suedkap_props.gd` (Alte Mole & Fluttor), Atlas-Kartenbake (`paint_zone_map.py`). | `tools/test_suedkap.tscn` & `tools/preview_suedkap.tscn` |
| **M6 · Eigene Szene `suedkap_gezeitenkammern.tscn` & Art** | Maßgeschneiderte Pixelart-Assets (Schiefer-Schleusenstein, Holzstege, Schiffsspanten, West-Flutglocke, Sporenstränge, Kran-Gegengewicht, 3 Steinpoller, Seetor, Szenen-Banner, Vorgath-Rig & 3 Sturmhafen-Items — neue Art über den Art-Subagenten nach Projektregel), `tide_water.gdshader`, alle 4 Abschnitte + Schmugglernische. | `tools/preview_suedkap_dungeon.tscn` |
| **M7 · Endboss *Vorgath*, Audio & End-to-End-Abnahme** | Boss-KI `Vorgath` (Kettenfeger, Brackwasser, Konter-Rammflut + Ersthinweis, `60 %` Taumel-Sog, `30 %` Springflut hinter Pollern, Laternen-Bruchstelle), *Ankertropfen*, *Gezeitenreif* & *Klinge der Hafenwache* in `data/items.json` / `talismans.json`, Audio-Synthese (`tools/audio_dungeon_suedkap.py`), kompletter Solo- & Koop-Durchlauf. | `tools/test_suedkap_dungeon.tscn` (headless + visuelle Captures) |
