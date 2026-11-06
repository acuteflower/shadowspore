# Nacht und Schattenwesen – Konzept

Status: **Stufen 1–6 gebaut, feste Risse später wieder entfernt (siehe §12)** (Stand 2026-11-05, siehe §11), neue Wesen (Stufe 7) laufen über eigene Besprechungen. Entscheidungen des Users zu §10 stehen dort. Grundlage: `TimeManager` (12 min Tag, davon 4 min Nacht, `night_amount()`), `VoidEdge` (Augenpaare am Weltrand), `ShadowSpider` / `VoidListener`, `EnemyScaling` + `MineEncounterDirector` (Muster für Spawn nach Budget), `TownManager` (Lichtkreise = Land), `Levels` / `ProgressComponent`, `WildlifeEvents` (Muster für einen rein host-seitigen Direktor).

## 1. Leitsätze

1. **Tag = Ruhe, Nacht = ihre Zeit.** Der Tag ist Aufbau und Erkundung, die Nacht ist der Druck.
2. **Licht ist Land.** In Lichtkreisen und um Gebäude entsteht nichts, und die Wesen meiden sie. Wer Land halten will, baut Licht.
3. **Die Nacht kommt in Wellen, nicht als Wand.** Dämmerung warnt, Einbruch ist laut, tiefe Nacht ist der Höhepunkt, Morgengrauen erlöst.
4. **Schwierigkeit hängt an Spielstand, nicht an Entfernung** (Projektregel „überall gleich schwer“). Sie wächst mit Level, Tag, Gesamtstärke und Spielerzahl.
5. **Alles ist lesbar:** Risse, Augen, Wildtiere und Geräusche kündigen an, bevor etwas passiert.

## 2. Der Tag: Tagesreste

- Schattenwesen sind tagsüber **extrem selten** (grob ein Rest je 3–4 geladene Chunks und Tag, global gedeckelt) und **stark geschwächt**: 40 % Leben, 60 % Schaden, langsamer, flackernde Körper, kein Fernangriff.
- Sie sind **Schattenflüchter**: halten sich in Hainen, an Wänden und Rissen, laufen vor Sonne in den Schatten und greifen nur an, was ihnen sehr nahe kommt.
- Sonne zehrt sie: **Sonnenwunde** (kleiner Schaden über Zeit außerhalb von Schatten), sie lösen sich bei Treffer sichtbar „angefressen“ auf. Das ist auch der Tag-Look der Wesen (Phase 5 in `tag_nacht_konzept.md`, die dort zurückgestellt ist).
- Funktion im Spiel: Wer tagsüber weit weg von der Basis ist, spürt, dass die Welt nicht sauber ist, und bekommt eine kleine, ungefährliche Übung. Dazu gehört auch das Anknüpfen an die Spinnenwächter der Story.
- Tagesreste lassen kein besonderes Loot außer wenig `void_splinter` (Leerensplitter, gibt es schon als Loot) (§7).

## 3. Der Nachtablauf

Die Nacht dauert nur 4 Spielminuten (`NIGHT_START` 5/6 bis `NIGHT_END` 1/6), plus je eine Minute Dämmerung. Deshalb Wellen im Takt von etwa 40–50 Sekunden.

| Phase | Zeit | Was passiert |
|---|---|---|
| **Vorzeichen** | letzte ~60 s Dusk | Hasen und Rehe gehen heim, Krähen warnen, Vogel- und Insektenklang erstirbt. **Die Risse im Boden beginnen zu glimmen** (`night_amount` ab ~0.3). Am Weltrand öffnen sich erste Augenpaare. Noch kein Spawn. |
| **Einbruch** | `night_amount` ≥ 0.6 | Erste Welle: Die Risse öffnen sich, Wesen schlüpfen (Emerge-Animation wie bei `spawn_story_spider`). Vom Weltrand kriechen Krabbler herein. Ein tiefer Ton, die Herzschlag-Schicht der Nacht-UI setzt ein. |
| **Tiefe Nacht** | Mitte | Höchstes Budget, die meisten Patrouillen, Elite-Riss möglich. |
| **Morgengrauen** | `night_amount` fällt unter 0.5 | Es werden keine neuen geboren. Wesen ziehen sich zu Rissen/Weltrand zurück. Beim Sonnenaufgang zerfallen übrige Wesen (Sonnenwunde stark), es bleibt Staub und kurz ein Hauch von Schatten auf dem Boden (`ShadowPatch`-Infestation). |

Spieler im Gebäude oder in der Mine bekommen davon nichts mit (Pocket-Räume sind weit weg, die Mine hat ihr eigenes System).

## 4. Woher sie kommen

**Spawn passiert lokal um die Spieler, nicht auf der ganzen Karte** (Welt ist 1100×1100 Tiles, nur etwa 3×3 Chunks sind geladen). Der Direktor wirft die Wesen in einem Ring von etwa 28–46 Tiles um jede Spielergruppe ab, an echten Quellen:

1. **Nachtrisse** (`CrackSite`): feste, pro Chunk deterministische Punkte (wie `PropGenerator`, aus Weltseed), tagsüber schlafende, kaum sichtbare Haarrisse mit schwachem Violett, **nachts** aufgehende, pulsierende Spalten. Jeder Riss hat eine Kapazität pro Nacht und einen Abkühl-Timer. Man lernt die Karte: „dort hinten ist wieder ein Riss“.
2. **Der Weltrand:** Krabbler aus dem Void, die ins Land wandern. Nahe am Rand ist die Dichte höher (aber **nicht stärker**, die Stärke hängt nicht von der Lage ab).
3. **Schatten unter Bäumen:** selten, einzelne Wesen schlüpfen aus tiefen Hainschatten (nur Kleinzeug, siehe §6).

**Sperrzone (Licht ist Land):** Kein Spawn, wenn die Position
- innerhalb eines Lichtkreises (Vereinigung von `reach` fertiger Bauten, Lampenpfähle, Lagerfeuer, Hütte) **plus 24 px Rand** liegt oder
- näher als 6 Tiles an einem Gebäude oder einer Baustelle ist,
- oder in der Mine/einem Innenraum.

Ein Riss in der Sperrzone ist **versiegelt** (bleibt dauerhaft ruhig, kleine Verkohlung). Wächst die Stadt über einen Riss, **gewinnt man Land zurück**: Das ist die sichtbare Belohnung fürs Bauen.

## 5. Wie viele und wie stark

Zwei getrennte Regler, damit „mehr“ und „stärker“ nicht dasselbe sind.

**Menge: Nachtbudget** je Spielergruppe (alle Spieler innerhalb ~80 Tiles = eine Gruppe, jede Gruppe hat ein eigenes Budget).

```
Budget = b0 · f_Level · f_Tag · f_Spieler
f_Level   = 1 + 0.10 · (Gruppenlevel − 1)       (Mittel der XP-Level, Levels.gd)
f_Tag     = min(1.5, 1 + 0.02 · (Tag − 1))      (TimeManager.day, leicht)
f_Spieler = n^0.8                                (Mehrspieler wächst, aber unterlinear)
```

Beispiel mit `b0` = 6: Level 1, Tag 1, solo → 6 (etwa vier Spinnen über die ganze Nacht). Level 10, Tag 10, vier Spieler → ~41. Jedes Wesen kostet Budget (Spinne 1, Lauscher 1.5, Elite 5, kleine Flackerer 0.3). Das Budget wird in Wellen freigegeben (30 % / 40 % / 30 %), nicht auf einmal. Lebende Wesen zählen gegen das Budget, wer eins tötet, macht im selben Wellenfenster Platz für Nachschub (verschiebbar, mit Cooldown), sodass „ausräuchern“ nicht endlos Gegner nachzieht. Harte Deckel: 24 lebende je Gruppe, 48 insgesamt (Navigation und Netz, `docs/performance.md`).

**Stärke:** über das bestehende `EnemyScaling` (`health_scale`, `damage_scale`):
```
Stärke = 1 + 0.06 · (Gruppenlevel − 1) + 0.15 · Gesamtstärke
```
`Gesamtstärke` = ein einziger Wert aus Ausrüstung/Waffe des besten Spielers (Spielerwerte, kein neues Stat-System), mit Deckel. Beide Regler sind **Daten** in `data/night.json`.

**Neue Arten durch Budget:** Ab Schwellen des Budgets und des Tages tauchen weitere Arten im Mix auf (§6). Also nicht „dieselben Gegner, nur zäher“, sondern ab Stufe X kommen neue Typen dazu.

**Fairness:**
- Das erste Level-1-Budget ist bewusst klein, der Spieler soll Licht bauen *wollen*, nicht müssen.
- Nach einem Tod in der Nacht sinkt das Budget der Gruppe für den Rest der Nacht auf 60 % (kein Teufelskreis).
- Einzelne Spieler weit weg von der Gruppe werden einzeln budgetiert.

## 6. Verhalten: Patrouille, Lichtscheu, Lockung

**Patrouille:** Außerhalb des Lichts wandern Wesen in der Dunkelheit: Ziele sind Risse, Weltrand, dunkle Haine und die letzten bekannten Spielerpositionen (Hörschwellen wie beim Lauscher). Sie bewegen sich durch `EnemyNavigation`, nur im geladenen Land (`WorldLevel.navigation_floor`). Sie sind **im Weltgeschehen sichtbar** (Augen im Dunkeln), ein Spieler kann sie umgehen, anschleichen oder jagen. Das Schleichen aus der Story (Spinnenwächter) bleibt der Lehrpfad.

**Lichtscheu (Standard):**
- Drei Zonen um die Basis: **Licht** (Kreise, Sperrzone), **Dämmersaum** (1.0–1.6 × `reach`, Wesen lungern hier, Augen am Rand sichtbar) und **Wildnis**.
- Wesen betreten das Licht normalerweise nicht, sie bleiben stehen, zucken und weichen zurück (**Lichtdruck**). Kommen sie doch hinein (gereizt, §6.3), sind sie im Licht **verlangsamt, flackernd, schwächer im Schaden** und lösen sich bei gezielten Treffern auf.

**Lockung:** Aktivität in der Basis erzeugt **Reiz** (Zahl je Basis und Nacht): Sprinten, Kämpfen, Hämmern/Bauen, mehrere Spieler, Kochfeuer, Lärm. Reiz sinkt langsam. Überschreitet er Schwellen, wagt eine Gruppe einen **Vorstoß**:
1. 15 Sekunden vorher: Augenpaare sammeln sich im Dämmersaum, tiefes Flüstern aus der Richtung (Warnung).
2. Angriffsrichtung bevorzugt **Lücken im Lichtnetz** (dunkle Stellen zwischen zwei Lampen). Wer klug plant, lenkt den Angriff in eine Falle.
3. Ein Vorstoß dauert begrenzt (max. ~20 s), danach Rückzug.

**Wesenstypen (was schon da ist, was Ideen sind):**
- Schon gebaut: Schattenspinne (Krabbler, Nahkampf), Void-Lauscher (Ferne, hört).
- Ideen, noch **nicht beschlossen**: *Flackerer* (kleine Schwärme, extrem lichtscheu, machen nur Druck am Rand), *Rissläufer* (schnell, patrouillieren zwischen Rissen), *Rissherz* (Elite, schlüpft nur aus großen Rissen in tiefer Nacht, bewacht den Riss bis zum Morgen), *Hirte* (Leerenwesen, das andere kleine Wesen lenkt). Jede Art bekommt ihre eigene Besprechung.

## 7. Belohnung und Rhythmus

- Nachtwesen lassen **Leerenstaub** (Material fürs Stadtwachstum oder Lichter, genaue Nutzung offen), wenige seltene Drops, normale XP. Tagesreste lassen kaum etwas.
- Die Nacht ohne Tod und mit gehaltener Basis gibt einen kleinen Bonus (ein „Nacht überlebt“-Moment am Morgen, Banner im Stil von `TownBanner`).
- **Sondernächte** (selten, ab Tag ~5, vorher angekündigt am Abend durch Wetter/Himmel): *Leerenflut* (viel, schwach, Flackerer), *Stille Nacht* (wenige Wesen, dafür ein Jäger, der gezielt nach Spielern sucht), *Nebelnacht* (Sicht kurz, Lichtkreise schrumpfen leicht, Augen sieht man erst spät). Die Gewichtung hängt am Tag.
- **HUD:** Eine Anzeige der „Nachtlage“ ist nicht nötig. Sie steckt im Welt-Bild: Rissglimmen, die Infektion der Reben (`VineStyle.infection` ist schon an `night_amount` gekoppelt) und der Weltrand.

## 8. Technik (Skizze, nicht gebaut)

- `NightDirector` (`src/systems`, Knoten im `WorldLevel`, **nur Host**, wie `WildlifeEvents`): liest Tageszeit, Gruppen, Budget, Risse, Lichtfeld und verteilt Spawns über das bestehende `WorldLevel.spawn_species`. Keine neue Netzlogik: Wesen replizieren über ihre Spawner.
- `data/night.json`: b0, Faktoren, Wellenanteile, Deckel, Kosten und Schwellen je Art, Ringradien, Sperrränder, Reizquellen. Alles tunebar ohne Code.
- `CrackSite` + Generator pro Chunk (wie `PropGenerator`, deterministisch, in der Chunk-Vorbereitung als Arbeitseinheit; Cancel/Unload gibt sie frei). Zustand (versiegelt, Kapazität) lebt im Direktor und wird gespeichert/gesnapshottet.
- **`LightField`-Abfrage**: eine einzige Funktion `TownManager.light_at(pos) -> float` (0 draußen, 1 mitten im Kreis), die die Sperrzone, Lichtdruck, Dämmersaum **und** die Nachtpatrouille speist. Die Lichtkreise gibt es schon (Platzierung), es fehlt nur die Abfrage von außen.
- Lichtscheu und Patrouille als kleine Komponente (`NightBehavior`) auf den Gegnern, sie bremst die vorhandene Zustandsmaschine, ersetzt sie nicht.
- Wildlife-Anbindung: Tiere und Krähen reagieren auf `night_amount` und auf Wesen in der Nähe als Frühwarnung (vorhanden: Alarm bei `predators`).
- Tests: `tools/test_night_director.tscn` (Budget-Rechnung, Sperrzone, Wellenfenster, Deckel, Tagesreste), Netzwerk-Check als Zwei-Prozess-Test wie bei den anderen Wesen.

## 9. Bauplan (jede Stufe einzeln abstimmen)

1. **Lichtfeld und Schutzregel** (`light_at`, Sperrzone, Lichtdruck). Rein Regeln, sofort testbar.
2. **Risse** (Generator, Tag-/Nachtdarstellung, Versiegeln im Licht) und **Nachtdirektor v1** (Einbruch, Wellen, Budget mit Level, bestehende zwei Arten).
3. **Skalierung** (Tag, Spieler, Stärke, Deckel, Fairness-Regeln).
4. **Patrouille und Lichtscheu**, danach **Lockung/Vorstoß**.
5. **Tagesreste** und Sonnenwunde, Morgengrauen-Zerfall.
6. **Sondernächte**, Belohnung (`void_splinter` (Leerensplitter, gibt es schon als Loot)), Banner.
7. **Neue Wesen** (eigene Besprechung je Art).

## 10. Entscheidungen (User, 2026-11-05)

1. **Schlafen:** Ein Bett überspringt die Nacht grundsätzlich NICHT, nur in den Questteilen der Story (wie bisher).
2. **Lichter mit Pflege (Brennstoff):** erstmal nein, für die Zukunft vorgemerkt (Memory `project_light_upkeep_future`).
3. **Gebäude beschädigen:** wie 2, erstmal nein, vorgemerkt. Lichter flackern nicht unter Druck, nichts geht kaputt.
4. **Gruppenlevel:** der Stärkste der Gruppe.
5. **Tod:** Respawn an der Basis (Haustür des Hauses; vor der Stadtgründung die Haustür der Hütte). Im Opening bleibt der Kanaldeckel.

## 11. Umsetzung (gebaut)

| Stufe | Was | Wo |
|---|---|---|
| 1 Licht ist Land | `TownRules.light_depth/light_outward/lit_fraction`, `TownManager.light_depth/spawn_blocked/dark_edge/is_building/respawn_point/banner`. Sperrzone: Lichtkreis + 24 px Rand, 6 Tiles um Gebäude mit `role` oder `reach` (Haus, Lager, Werkstatt, Laternen; Zäune und Platten nicht). | `src/town/` |
| 2 Risse + Direktor | `NightCracks` (deterministisch pro 32er-Chunk, 0–2, nur auf Land/ebenem Boden/ohne Wasser: `WorldLevel.crack_ground`), `CrackField` + `CrackSite` (Bild, jeder Peer; offen nach `night_amount`, versiegelt in der Sperrzone), `NightDirector` (nur Host, Tick 0,5 s). Quellen: Risse (Kapazität 3 pro Nacht) und Küstenstreifen; Ring 22–46 Tiles um die Spieler. Spawn über `WorldLevel.spawn_species(..., emerge)`. | `src/world/` |
| 3 Skalierung | `NightRules`: Budget (Level des Stärksten, Tag, Spielerzahl^0.8), Stärke über `EnemyScaling`, Wellen 30/70/100 %, Deckel 24/48, Kill gibt 50 % zurück, nach einem Tod 60 % Budget, Arten nach Budget/Level/Tag. Alle Zahlen in `data/night.json`. | `src/systems/night_rules.gd` |
| 4 Verhalten | `NightBehavior` (Patrouille, Lichtdruck: stoppt am Rand, im Licht gebremst und hinausgeschoben, ein Vorstoß darf hinein). Haken in `ShadowSpider` und `VoidListener` (`night`-Variable, nur Host). Lockung: Sprinten, Schwingen, Bauen, mehrere Spieler; Schwelle 45 → Warnung 15 s (Banner, Sammeln am Dämmersaum) → Vorstoß 22 s durch die dunkelste Lücke → Ruhe. Dev: Escape → ENTWICKLER → VORSTOSS AUSLÖSEN. | `src/components/night_behavior.gd`, `night_director.gd` |
| 5 Tag/Morgen | Tagesreste (40 % Leben, 60 % Schaden, 70 % Tempo, nur im Schatten von Bäumen, Sonnenwunde außerhalb), Morgengrauen: alles dreht Richtung Riss und verbrennt, ohne Beute. | `night_director.gd` |
| 6 Sondernächte, Belohnung | `flood` (Leerenflut: 1,6× Budget, schwächer) und `silent` (Stille Nacht: 0,4× Budget plus ein Jäger, der gezielt nach Spielern sucht), ab Tag 4, 20 %, deterministisch aus Weltseed und Nachtnummer, Banner am Abend. Morgens „NACHT ÜBERSTANDEN“ und etwas XP für Gruppen ohne Tod. | `night_director.gd` |

**Aktiv** sind die Nächte erst, wenn die Stadt gegründet ist (`rebuild_done`) und das Opening vorbei ist. Davor führt die Story und es gibt keine Nachtwesen.

**Nicht gebaut / bewusst offen:** Nebelnacht (schrumpfende Lichtkreise, Sichtweite), Flüstern/Ton vor dem Vorstoß (nur Banner), Spawn aus Hainschatten, Tutorial-Karte für die erste Nacht, Speichern der Nacht (Budget und Vorstoß beginnen nach dem Laden neu), neue Wesen (Flackerer, Rissläufer, Rissherz, Hirte: je eine eigene Besprechung; der Leerenbrecher läuft in einer anderen Session). Tests: `tools/test_night.tscn --fixed-fps 60`.

## 12. Änderung: keine festen Risse mehr (2026-11-05)

Die festen, sichtbaren Nachtrisse (§4 Quelle 1, `NightCracks`, `CrackField`, `CrackSite`) sind entfernt. Stattdessen nutzen die Wesen ihre **eigene Geburtsanimation**: Die Spinne steigt mit `ShadowBirth` aus dem Boden (`emerge_on_spawn`), Lauscher und Brecher blenden mit einem Schattenfleck ein. Spawnpunkte sind zufällige freie, dunkle Punkte im Ring von 22–46 Tiles um die Spieler (65 %) oder nahe der Küste (35 %). Sperrzone und alles andere bleiben. Folgen: Patrouillen kehren manchmal zum Geburtsort zurück (`home_chance`), und beim Morgengrauen fliehen die Wesen von den Spielern weg in die Dunkelheit. Die Spawn-Quelle „Riss“ in den Abschnitten oben (§3, §4, §8, §11) ist damit überholt; „Land zurückgewinnen durch Versiegeln“ entfällt.
