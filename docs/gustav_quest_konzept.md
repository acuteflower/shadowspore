# Gustavs Rettung und die Werkstatt: Questkonzept

Stand: 2026-11-09. Status: **eingebaut (2026-11-09)**, siehe Abschnitt „Umsetzung“ am Ende. Vorher: Konzept. Alle Texte unten sind Platzhalter für den Dialog-Writer (`docs/prompts/dialogue_writer.md`, Dossier `docs/characters/gustav.md`). Figuren-Art (Gustav-Clips, Wagen) liefert der Art-Agent, nicht der Code-Agent.

---

## 1. Warum

Heute (`town_start` in `data/quests.json`) baut Ellie Lichtpfosten und Werkstatt, und danach **läuft Gustav einfach aus dem Nichts ins Licht** (`TownManager._check_arrivals`, `settlers.json` `arrive.needs: workshop`). Das ist technisch sauber, aber erzählerisch ein Fremder, der erscheint, weil ein Gebäude steht. Außerdem bekommt Ellie Sichel und Spitzhacke schon von Valdric (`town_intro` → `give`), obwohl beides Gustavs Handwerk ist.

**Neu:** Gustav wird **gefunden, gerettet und nach Hause begleitet**. Erst danach gibt es die Werkstatt, und Gustav gibt ihr die Sichel. Die Spitzhacke stellt sie später an seiner Werkbank selbst her.

Das schließt an Bestehendes an und wiederholt es bewusst gespiegelt:

| Früher | Jetzt |
|---|---|
| Ellie wird von Valdric aus der Falle gerettet (Hinterhalt am Wegweiser) | **Ellie rettet jemanden** und kämpft dabei selbst |
| Ellie klopft in der Intro-Szene von innen an den Kanaldeckel | **Gustav klopft von innen an die Wagenwand**, das Klopfen führt sie zu ihm |
| Valdric führt sie zur Hütte (`follow_knight`) | **Ellie führt Gustav** zum Licht |
| Das Licht ist ein Werkzeug (Spawnsperre) | Das Licht ist das **Ziel**: „Licht ist Land“ wird spürbar |

---

## 2. Überblick: die Kette

```
town_start (DIE STADT, gekürzt)
  Nacht abwarten → Valdric → Gespräch (ohne Werkzeuggabe) → LICHTPFOSTEN BAUEN
        │ next
        ▼
gustav_rescue (DER FREMDE IM OSTEN, neu)
  Valdric schickt sie → Klopfzeichen folgen → Wagen sehen → Spinne besiegen
  → Wagentür lösen → Gustav kennenlernen → ZUM LICHT BEGLEITEN (3 Angriffswellen, Dämmerung)
  → Begrüßung am Licht (Valdric + Gustav)
        │ next
        ▼
town_workshop (DIE WERKSTATT, neu)
  Gustav gibt die Sichel → HOLZ / STEIN / FASERN sammeln → WERKSTATT BAUEN
  → Gustav zieht in die Werkstatt → SPITZHACKE HERSTELLEN (erster Handwerksauftrag)
```

Die Gesamtdauer liegt bei etwa 20 bis 25 Minuten Spielzeit, davon ca. 6 Minuten Rettung und Eskorte, der Rest Sammeln und Bauen.

---

## 3. Quest 1: `town_start` (gekürzt)

Die Schritte `town_night`, `town_valdric`, `town_intro`, `build_lamp` bleiben. **Entfernt** werden `build_workshop`, `meet_stranger`, `gustav_hello`, die wandern in die neuen Quests. Neu: `"next": "gustav_rescue"`.

Änderung in `town_intro` (`data/dialogue.json`):
- `give` (Sichel, Spitzhacke) **entfällt komplett**. Auch die Zeile „Und nimm das hier: eine Sichel für Fasern, eine Spitzhacke für Stein…“ fällt weg.
- Neue Zeile (Valdric, beiläufig): *„Gestern Abend, weit im Osten: Holz, das splittert. Dann Klopfen. Dann nichts mehr.“* Das ist der **Anker** für die nächste Quest, er sagt es hier nur, ohne Auftrag.
- Die Axt hat sie schon, Schwert ebenfalls (Abend am Feuer). Die Spitzhacke braucht sie bis zur Werkstatt nicht (siehe 6.3).

---

## 4. Quest 2: `gustav_rescue` („DER FREMDE IM OSTEN“)

### 4.1 Schritte

| # | Step-ID | Text im Questlog | Typ | Abschluss / Event |
|---|---|---|---|---|
| 1 | `rescue_call` | SPRICH MIT VALDRIC | flag | Event `story:gustav_call`, Flag `gustav_call_done` |
| 2 | `follow_knocks` | FOLGE DEM KLOPFEN | reach | Ziel Wagen, `search` 30 Tiles, Flag `wagon_seen` per Sichtprüfung |
| 3 | `kill_wagon_spider` | BESIEGE DIE SCHATTENSPINNE | flag | `wagon_spider_dead`, Event `wagon:fight` |
| 4 | `free_gustav` | BEFREIE DEN EINGESCHLOSSENEN | flag | E am Wagen, `wagon_opened` |
| 5 | `gustav_meet` | SPRICH MIT DEM FREMDEN | flag | Dialog `gustav_rescue_a`, Flag `knows_gustav`, Dialog `_b`, `gustav_packed` |
| 6 | `escort` | BRINGE GUSTAV ZUM LICHT | flag | Event `escort:gustav`, Flag `gustav_at_light` |
| 7 | `welcome` | SPRICH MIT VALDRIC UND GUSTAV | flag | Event `story:gustav_welcome`, Flag `gustav_joined` |

### 4.2 Schritt 1: Valdric schickt sie

Der Lichtpfosten brennt. Valdric steht darunter: *„Dein Licht brennt. Und da: hörst du das?“* Kein lauter Moment: ein **dumpfes dreifaches Klopfen**, sehr fern, aus Osten (positionales Audio, erst hörbar, wenn sie weit genug im Osten ist, bis dahin nur der Hinweis im Dialog). Er sagt, er bleibe bei Hütte und Licht. Der Grund muss die Spielerin überzeugen:
- Das Licht ist neu und der Rand sein Posten („Jemand muss es halten, bis es sich selbst hält“).
- Er traut ihr das zu (Schwert, Axt, der Kampf in der Hütte des Holzfällers).
- Er gibt ihr **keinen** Ausrüstungsgegenstand und keine Karte, nur eine Richtung. Die Karte (M) zeigt ein Suchgebiet mit Rand.

Marker: Mitte **Tile (884, 689)**, Suchradius 30 Tiles (Vine: „SUCHKREIS 30 M“), gleiche Mechanik wie `find_knight` und `find_lumberjack`.

### 4.3 Schritt 2: Dem Klopfen folgen

Der Ort wurde aus den gebackenen Karten gesucht (nicht handgemalt): 99 Tiles Luftlinie östlich der Hütte, **Level 0, 17×17-Tile-Umgebung zu über 99,5 % flach**, 15,9 Tiles Küstenabstand, **107 Tiles Fußweg** über Level 0 vom Hof der Hütte. Flüsse sind noch nicht gegengeprüft, siehe Risiken (11).

**Klopfsignal** als Wegweiser: alle ca. 7 s drei Schläge Holz auf Holz, `PositionalAudio` (`tools/audio_gustav.py`, neu), hörbar ab ca. 300 px. Es gibt bewusst nur Ton und keine UI-Hilfe, die Spielerin soll hören. Es klingt wie Ellies Klopfen an den Deckel, mit etwas tieferem Holz. Nähert sie sich, bricht das Klopfen ab, sobald die Spinne in Hörweite ist (Gustav hält die Luft an). Das ist das Signal „jetzt Vorsicht“.

Sicht-Flag `wagon_seen` wie `Quarry._check_sight`: im Bild, ≤ 260 px, Strahl auf Layer 1 frei. Dann Bark (SpeechBox) `wagon_spotted` („Ein Wagen. Auf der Seite. Und was kratzt da dran?“).

### 4.4 Der Fundort: der umgestürzte Stellmacherwagen

Ein **kleiner Planwagen auf der Seite** (Hinterrad gebrochen, Achse gesplittert), die Plane zerrissen, vom Schatten angefressen: am Rand schwarzes Wachstum, violette Adern, ein paar Glimmpilze am Holz. Er ist Gustavs eigener Wagen und zeigt seinen Beruf: offene Werkzeugkisten, Hobelspäne, halbfertige Speichenräder, an der Wand Dachlatten. Er liegt in einem kleinen Hain (Bäume liefern Schatten, siehe 4.5).

Neue Props (`data/ground.json` neuer Block `wagons`, gleiches Muster wie `huts`/`quarries`):
- `GustavWagon` (`src/entities/props/gustav_wagon.gd`, `Interactable`, E „TÜR LÖSEN“ nur im Schritt `free_gustav`), solide, mit zwei Zuständen (verklemmt/offen), `HutYard`-Props rundum (Räder, Kisten, Latten), Glimmpilze als Glow-Sheet, kleines Nachtlicht.
- Hofboden per `tools/bake_ground.py --yards` (`palette: "dirt"`, Radspuren, die aus Westen kommen = der Weg, den er genommen hat).
- `clear_radius` 12, damit der Wagen nicht in generierte Bäume ragt.

### 4.5 Schritt 3: Die Spinne

Eine normale `shadow_spider` (48 HP, echter Kampf, keine Tricks), **ein** Gegner. Sie ist **am Wagen beschäftigt**: kratzt an der Plane, reißt Latten ab. Das gibt ein Zeitfenster und belohnt den Schleichen-Unterricht vom Anfang:

- Schleicht sie sich heran (Sichtweite der Spinne 62 statt 125), bleibt die Spinne beim Wagen, und der **erste Schlag landet unbemerkt**.
- Läuft sie, bemerkt die Spinne sie früher, der Kampf beginnt offen.
- Die Spinne greift im Kampf nur sie an, nie den Wagen.

**Gustav kommentiert aus dem Wagen** (SpeechBox, kurze Rufe, gedämpft, kein Pause-Dialog): „Links, Kindchen, links!“, „Hinter dir!“, „Autsch, das war meiner Schulter nicht gesund“. Rufe nur alle 4 bis 6 s, nie während eines Windup-Locks, kein Spoiler der Angriffsfolge. Der Tonfall hilft ihr, ohne zu bevormunden.

Kampf-Absicherung (damit niemand hängen bleibt): stirbt sie, normaler Respawn am Stadtlicht; Gustav klopft weiter, die Spinne ist wieder da und steht am Wagen. Kein Verlust außer Weg.

**Tag/Nacht:** Das Schatten-Wesen steht am Tag nur im Schatten der Bäume (bestehende Regel: Tagesreste halten sich im Schatten von `bird_perches`). Der Wagen liegt deshalb im Hain. Verlässt die Spinne den Schatten, brennt sie wie jede Tagesspinne, das wird hier nicht geändert, sie jagt aber einen Schritt weit in die Sonne und kehrt zurück (siehe Risiken).

### 4.6 Schritt 4: Die Tür lösen

Die Hecktür des Wagens klemmt, ein verbogener Balken hängt davor (wie das Brett an der Holzfällerhütte, anderes Bild, andere Handlung). E → Ellie läuft hin, geht in die Hocke (`Player.begin_pick`), zieht den Keil, die Tür springt auf, Staub, Knarren, dann (Gustav drinnen) ein überraschtes „Ho!“. Wiederverwendung: `CabinBoard`-Muster mit `begin_pick`, **kein neues Spielerclip nötig**.

### 4.7 Schritt 5: Gustav lernt man kennen

Er stolpert heraus, im Bart Holzspäne, eine Wagenlatte in der Hand wie eine Keule, und fragt als Erstes, ob sie friert. Der Bleistift-Witz aus dem alten `gustav_hello` zieht hierher um (hinterm Ohr, Ellie sieht es zuerst).

Dialog in zwei Teilen (Trick wie `knight_meet_a/b`):
1. `gustav_rescue_a`: Sprecher **„FREMDER“** (Silhouette, `known_flag knows_gustav`). Er dankt laut und viel, will wissen, ob jemand verletzt ist, erwähnt „meinen Wagen, meine Mädchen (die Räder)“ und nennt zuletzt seinen Namen. Danach setzt der Dialog das Flag `knows_gustav`.
2. `gustav_rescue_b`: Sprecher **GUSTAV** (Porträt aktiv). Er sagt, was er ist: **Zimmermann, Stellmacher, Allround-Bauer**, wandert seit Jahren von Dorf zu Dorf, alle sind umgefallen. Ellie erzählt vom Licht, der Hütte, Valdric. Er will sofort mit („Ein Dach? Mit Fuge?“). Schlussnote: er packt nur das Nötigste (die schwere Werkzeugkiste kann er nicht tragen, er trägt sie doch), der Wagen bleibt als Wrack (Prop bleibt dauerhaft, später vielleicht Ersatzteile).

`gustav_packed` ist gesetzt, die Eskorte beginnt automatisch nach dem Dialog.

**Wichtig für das Flag:** das alte `known_flag: "gustav_joined"` in `gustav_hello` wird auf `knows_gustav` umgestellt. `gustav_joined` bedeutet jetzt: ist Einwohner (am Licht angekommen).

### 4.8 Schritt 6: Die Eskorte (das Herzstück)

Technik: wie `KnightWalkScene`, nur umgekehrt. **Gustav folgt ihr.** Er wird von einem unsichtbaren `CharacterBody2D`-Läufer mit `EnemyNavigation` bewegt (gleiches A* wie Gegner, Wegpunkte höchstens 190 px voraus).

- **Tempo:** etwas langsamer als Ellies Gehen (Faktor ~0,85, einstellbar), er keucht. Weiter weg als 150 px: er bleibt stehen, ruft; unter 95 px läuft er weiter (gleiches Muster wie Valdric).
- **Ziel:** nicht fest, sondern der **nächste Punkt innerhalb des Lichts** (`TownManager.light_depth(pos)` > 24 px). Funktioniert, egal wo der Lichtpfosten steht.
- **Zeit:** direkt nach `gustav_packed` fährt die Uhr sanft auf **0,80** (Dämmerung, 6 s Beschleunigung mit Banner „DIE DÄMMERUNG KOMMT“, derselbe Mechanismus wie der Zeitraffer am Hütten-Finale). Der Weg zurück liegt also im Abend, die letzten Meter in Nacht-Stimmung (Augenpaare im Dunkeln wie im Hinterhalt, `AmbushEyes`). Der `NightDirector` wird für die Eskorte **gehalten** (`story_hold`), die Szene spawnt selbst.
- **Gustav ist unverwundbar** (`HealthComponent.floor_value` 1, wie sie beim Hinterhalt). Ein Treffer wirft ihn nicht um, er **taumelt**: kurzer Stolper, „Aua“-Bark, die Spinne wechselt nach 1,2 s wieder auf Ellie. Er kann nicht sterben und die Quest nicht scheitern.
- **Gustavs Hammer:** er trägt einen Vorschlaghammer (Dossier: schützt, was er gebaut hat). Greift eine Spinne ihn an und steht in seiner Reichweite, schlägt er **einmal pro 6 s** zu (12 Schaden, Rückstoß leicht). Das ist ein Gag, kein Kampfsystem. Der Hammer kommt in keinem Inventar vor.

Drei Wellen (alle echt kämpfbar, host-gesteuert via `WorldLevel.spawn_story_spider`, Beschwörung mit voller Emergence):

| Welle | Position | Gegner | Zweck |
|---|---|---|---|
| 1 | ca. 25 % der Strecke | 1 Spinne vorne auf dem Weg | Aufwärmen. Gustav duckt sich hinter einen Baum und bleibt stehen |
| 2 | ca. 55 % | 2 Spinnen von den Flanken, eine geht auf Gustav | Schützen lernen. Danach Pause: Gustav teilt Brot und Beeren (Heilung ~40 %), Ruhemoment |
| 3 | ca. 85 %, am Lichtrand | 1 Spinne | Lauf zum Licht. Die Spinne **stoppt an der Lichtkante** (Gegner betreten das Licht nicht), Ellie erledigt sie, Valdric steht am Rand des Lichts und **greift nicht ein**: er nickt nur |

Es gibt nie mehr als **2 gleichzeitig lebende** Spinnen. Gesamtgegnerzahl: 4. Die Werte entsprechen dem Standard (`shadow_spider`, 48 HP, Nahangriff 14, Greifer 17), nichts wird vervielfacht.

Wenn Ellie fällt: Respawn am Licht (Stadt-Regel), die Welle wird lautlos aufgelöst (Schatten zerfällt), Gustav bleibt am letzten Checkpoint stehen. Schritt wechselt zu „GEH ZURÜCK ZU GUSTAV“ (reach Akteur `gustav`), die Eskorte setzt an der **Welle, in der sie fiel**, wieder ein.

Beim Einsteigen von Spielern im Co-op: nur Host und lokale Spielerin (wie alle Story-Szenen bisher), siehe Risiken.

### 4.9 Schritt 7: Die Begrüßung am Licht

`story:gustav_welcome`, kurze Szene am Lichtpfosten (kein Schwarzbild):
- Valdric kommt einen Schritt auf sie zu. Gustav mustert den Eisernen: *„Sag mal, schwitzt du da drin eigentlich…“* Der erste Aufzieh-Gag am Valdric, der darauf nur das Visier ein Stück weiter senkt. („Herr Blechmann“ fällt hier zum ersten Mal.)
- Gustav sieht die erneuerte Hütte, die Fuge (die Zeile „Die Fuge hier hat jemand mit Liebe gesetzt. Nicht mit Verstand, aber mit Liebe“ aus dem alten `gustav_hello` bleibt hier erhalten).
- Gustav: *„Ein Dach, ein Licht und sonst nichts. Wo ist die Werkbank?“* Ellie: *„Wir haben keine.“* Gustav: **„Dann bauen wir eine.“** Er zählt auf, was er braucht (Holz, Steine, Fasern), und gibt ihr **seine Sichel** (`give sickle_basic`, Flag `sickle_given`).
- Valdric bietet an, eine Bettstatt am Feuer herzurichten.
- Flag `gustav_joined`. Gustav wird Einwohner (siehe 7.2) mit Start-Vertrauen 10.

---

## 5. Quest 3: `town_workshop` („DIE WERKSTATT“)

### 5.1 Schritte

| # | Step-ID | Text | Typ | Details |
|---|---|---|---|---|
| 1 | `ws_gather` | MATERIAL FÜR DIE WERKSTATT | tasks | drei Aufgaben (siehe 5.2) |
| 2 | `ws_build` | BAUE DIE WERKSTATT | flag | `built_workshop`, `hint: "build"` |
| 3 | `ws_movein` | SPRICH MIT GUSTAV | flag | Event `story:workshop_done`, Flag `workshop_done` |
| 4 | `ws_pickaxe` | STELLE EINE SPITZHACKE HER | flag | `crafted_pickaxe`, `hint: "craft"` |

### 5.2 Sammeln

Die Werkstatt kostet 24 Holz, 10 Stein, 4 Faser (`data/town.json`). Die drei Aufgaben als `tasks` (Zähler wie 7/20 am QuestVine):

| Aufgabe | Wie sie es bekommt | Werkzeug |
|---|---|---|
| **HOLZ** 24 | Bäume fällen (Fichte etwa 5 Holz) | Axt (hat sie) |
| **STEIN** 10 | **Kiesel** aufsammeln (E, Pick-Animation, Kiesel liegen überall) | keins |
| **FASERN** 4 | Flüstergras mit der **Sichel** schneiden (2 Schläge pro Büschel) | Sichel (von Gustav) |

Hier liegt die Idee, die die Spitzhacke **natürlich sperrt**: *„Für Felsen brauchst du die Spitzhacke. Die mach ich dir, sobald die Bank steht. Kiesel tun’s für den Anfang.“* Kein Item wird versteckt, es gibt nur einen Zeitpunkt, ab dem ein Werkzeug sinnvoll wird.

**Task-Art `stock`** (neu): zählt Beutel **plus Stadtlager** (die Kosten nimmt der Bau zuerst aus dem Lager, siehe `docs/town.md`). Sonst sähe man 24/24 und nach dem Einlagern im Lager wieder 0.

Gustav hilft währenddessen mit Zeilen (`chat` nach Quest-Schritt), er sitzt am Feuer, schnitzt (Animation `work`/`split`), nimmt keinen Handschlag selbst vor, solange sie sammelt: *„Wenn du Holz bringst, schnitz ich Pläne. Fair?“*

### 5.3 Bauen und Einzug

`ws_build` nutzt den vorhandenen Baumodus (`B`), die Werkstatt ist freigeschaltet (`unlock`, siehe 7.4) und muss im Licht stehen (Standardregel, `check_place`). Helfer: Valdric und Gustav helfen mit (bestehendes „Helfer in der Nähe“-System: das Haus wächst schneller, wenn jemand daneben steht); Gustavs `work`-Clip am Bauplatz ist der Moment, in dem man ihn zum ersten Mal richtig arbeiten sieht.

Ist die Werkstatt fertig, läuft Gustav zur Werkbank (sein Plan wechselt von „Lager“ zu „Heimat“), Szene `workshop_done`: er streicht über die Bank, lobt die Fuge (wenn die Zeile nicht schon am Licht verbraucht ist, Alternative: *„Das Brett hast du schief genagelt, Kleines. Ich liebe es.“*), erklärt in zwei Sätzen, dass er jetzt hier arbeitet und **dass sie bei ihm herstellen kann, was sie selbst kann** (`by: self`-Rezepte) **und was er schmiedet** (`by: npc`, mehr Vertrauen).

### 5.4 Erste Herstellung: die Spitzhacke

`ws_pickaxe`: die Werkbank öffnet das `ShopWindow` (Craft-Tab). Die Spitzhacke ist im Tab hervorgehoben (Hinweis-Karte `hint: "craft"`), Kosten 2 Holz + 3 Stein (`recipes.json`, `once: true`, `by: self`). Ist sie hergestellt, setzt der Handwerkshaken `crafted_pickaxe`, Gustav kommentiert („Gut gemacht, Wirbelwind.“). Damit endet die Kette. Danach sind Felsen, die Mine am Steinbruch (`old_mine`, Tile (736, 736)) und die Spitzhacken-Wege offen, **aber nichts davon wird hier erzwungen**.

Nicht Teil dieser Kette: Eisenschwert, Schmiede, weitere Rezepte (`sword_iron`, Vertrauen 20).

---

## 6. Was sich für Werkzeuge und Spielgefühl ändert

### 6.1 Sichel und Spitzhacke

- **Sichel:** Gustavs Geschenk am Licht (4.9). Bis dahin kann sie Gras nicht schneiden (Fasern, Klee in Stücken), was vor der Werkstatt nirgends gebraucht wird. Ab `gustav_joined` ist sie da.
- **Spitzhacke:** nur noch über die Werkbank. Wer vorher einen Felsen anschlägt, bekommt den bekannten Rustle ohne Ertrag (bestehendes Verhalten bei falschem Werkzeug).
- `data/loadout.json` (Arena-Testausrüstung) und die Mine bleiben unverändert.

### 6.2 Dem Neuling nichts wegnehmen

Wer einen alten Spielstand mit Sichel und Spitzhacke hat, **behält sie**. Die Änderung gilt nur für neue Verläufe und Speicherstände, die noch nicht an `town_intro` vorbei sind (Migration unter 8).

### 6.3 Stein ohne Spitzhacke

Zehn Stein aus Kieseln sind etwas Gehen. Kiesel liegen verteilt (`lone_stone`, nach 3 Tagen wieder da). Falls die Zahl zu zäh wirkt, ist der saubere Hebel die Menge Stein pro Kiesel (`plants.json`, `pickup`), nicht eine Sonderregel für die erste Werkstatt. Erst messen, dann entscheiden.

---

## 7. Technische Umsetzung

### 7.1 Datenänderungen (alles datengetrieben, wie bisher)

| Datei | Änderung |
|---|---|
| `data/quests.json` | `town_start` kürzen (+`next`), neue Quests `gustav_rescue`, `town_workshop` |
| `data/dialogue.json` | `town_intro`: `give` raus, Zeilen anpassen. Neu: `gustav_call`, `gustav_rescue_a/_b`, `gustav_welcome` (`give` Sichel, Flag), `workshop_done`; Barks `wagon_spotted`, `escort_*` |
| `data/settlers.json` | `gustav.arrive` → `story: "gustav_joined"` statt `needs: workshop`; neuer `camp`-Plan (siehe 7.2) |
| `data/ground.json` | neuer Block `wagons` (Tile 884/689, `clear_radius`, Hofprops), eventuell Fahrspur-Pfad |
| `data/recipes.json` | unverändert (Spitzhacke bleibt `once`, `by: self`) |
| `data/town.json` | `workshop.unlock` an `gustav_joined` knüpfen (siehe 7.4) |

### 7.2 Gustav als Einwohner vor der Werkstatt

`Settler.home` ist die Werkstatt, die aber noch nicht steht. Lösung wie bei Valdric (`founder`, `takes_over`):
- `TownManager._check_arrivals` überspringt Siedler mit `story`-Schlüssel (kein automatischer Zuzug mehr).
- Neue Host-Funktion `TownManager.add_story_resident(sid, trust)` → `_rpc_resident(sid, {trust, talked: -1}, false)` am Ende von `story:gustav_welcome` (nicht „frisch“: er geht nicht noch einmal vom Rand herein, er steht schon am Licht).
- `settlers.json` bekommt `schedule_camp` (greift, solange `home` nicht gebaut ist): tagsüber Spots `fire`/`split`/`bench` (Splitten am Stapel, Sitzen auf der Bank, vorhandene Spots), nachts `rest` = **am Feuer** (`fallback` auf `fire`, gleiche Auflösung wie `Settler.resolve_spot`). Sobald `has_built("workshop")`, wechselt er auf den normalen Plan, `produces` greift (zwei Bretter pro Stunde) erst dann.
- Spielerin kann mit ihm reden; sein Talk-Pool kennt den Quest-Schritt (`chat` nach `step_id`).

### 7.3 Neue Code-Bausteine

| Baustein | Aufgabe | Vorbild |
|---|---|---|
| `GustavWagon` (`src/entities/props/gustav_wagon.gd`) | verklemmte Tür, E „TÜR LÖSEN“, Zustände, Glow | `CabinBoard`, `Hut` |
| `GustavRescueScene` (`src/entities/player/gustav_rescue_scene.gd`) | Wagenkampf, Barks, Türszene, Dialogteile | `CabinSpiderScene`, `KnightMeetScene` |
| `GustavEscortScene` (`.../gustav_escort_scene.gd`) | Läufer, Wellen, Checkpoints, Dämmerung, Unverwundbarkeit | `KnightWalkScene`, `AmbushScene` |
| `WorldLevel.start_gustav_rescue/start_escort/start_welcome` | Event-Einstiege, Wiederaufnahme in `resume_story` | `start_cabin_spider`, `start_knight_walk` |
| Sichtprüfung `wagon_seen` | wie `Quarry._check_sight` | |
| Task-Art `stock` in `QuestComponent` | Beutel + Lager zählen | `deliver` |
| Craft-Haken | `TownManager` setzt nach einer Herstellung das Flag `crafted_<rezept>` (nur lokal bei der Spielerin) | `built_<piece>` |
| `NightDirector.story_hold` | hält die Wellen, solange die Eskorte läuft | `begin_story` |

### 7.4 Werkstatt-Freischaltung

Der Baumodus bietet die Werkstatt heute schon an, sobald die Stadt gegründet ist. Neu: sie ist **gesperrt (`BRAUCHT: GUSTAV`)**, bis `gustav_joined` gesetzt ist, damit niemand die Werkstatt vor der Rettung baut und der Ablauf nicht kippt. Ein Spieler, der trotzdem früh über Debug baut, wird abgefangen (siehe Migration).

### 7.5 Wiederaufnahme (`resume_story`)

| Gespeicherter Schritt | Was beim Laden passiert |
|---|---|
| `kill_wagon_spider` | Spinne am Wagen wieder da |
| `free_gustav` | Wagen steht verklemmt, Spinne tot |
| `gustav_meet` | Wagen offen, Gustav davor |
| `escort` | Gustav am Checkpoint der letzten Welle |
| `welcome` | beide am Licht |
| `ws_*` | Gustav am Feuer (bis die Werkstatt steht), dann an der Werkbank |

### 7.6 Entwickler-Sprung

`WorldLevel.debug_jump_town()` (STORY-SPRUNG → FERTIGE STADT) setzt neu: alle Quests bis `ws_pickaxe` erledigt, **nur Sichel** im Beutel (Spitzhacke fehlt, damit man sie herstellen kann), Werkstatt gebaut, Gustav an der Bank. Zusätzlich neuer Sprung **GUSTAV GERETTET**: Quest bei `ws_gather`, Gustav am Feuer, Sichel im Beutel.

---

## 8. Migration alter Spielstände

| Stand im Save | Folge |
|---|---|
| vor `town_intro` | neuer Ablauf, Sichel/Spitzhacke werden nicht mehr gegeben |
| `build_lamp` oder `build_workshop` aktiv, Werkstatt noch nicht gebaut | neuer Ablauf ab `gustav_rescue` |
| Werkstatt gebaut oder Gustav bereits Einwohner (`residents.gustav`) | Quests `gustav_rescue` und `town_workshop` gelten als erledigt, `gustav_joined`/`knows_gustav`/`sickle_given` gesetzt, Sichel nachgegeben falls fehlt, Spitzhacke bleibt wie sie ist |
| Flag `town_intro_done`, Sichel/Spitzhacke schon im Beutel | bleiben im Beutel |

---

## 9. Art- und Audio-Bedarf (Art-Agent, nicht Code-Agent)

**Gustav** (`assets/characters/gustav.png`, aktuell 22 Frames: `idle`, `walk`, `run`, `work`; Rig `data/gustav_rig.json`; Porträt `assets/ui/portrait_gustav.png` ist vorhanden). Neue Clips:

| Clip | Wo |
|---|---|
| `peek` (spähend aus dem Wagen, geduckt) | Kampf am Wagen, kurz |
| `stumble_out` (aus der Tür, Latte in der Hand) | Schritt 4/5 |
| `hold_hammer` / `swing` (Vorschlaghammer) | Eskorte |
| `duck` / `crouch` | hinter Baum |
| `pant` (Hände aufs Knie, Atem) | Pausen |
| `sit` | Lager, Bank, Feuer |
| `carry_chest` (Kiste in der Hand) | Eskorte |

**Wagen** (`tools/art_gustav_wagon.py`, gleiche Ellipsoid-Pipeline): zwei Zustände (Tür verklemmt/offen), Glow-Sheet (Pilze, violette Adern), Hofprops (Räder, Latten, Werkzeugkisten, Hobelbank-Reste).

**Audio** (`tools/audio_gustav.py`): Klopfen (drei Varianten), Tür springt auf, Latte splittert, Gustav-Ausrufe (ohne Sprachausgabe, Brummen/Husten als Platzhalter), Hammerschlag auf Spinne.

---

## 10. Tests

- `tools/test_gustav_quest.tscn` (headless, `--fixed-fps 60`): Kette von `build_lamp` bis `crafted_pickaxe`, ohne Sichel/Spitzhacke vor `gustav_welcome`, `give` genau einmal, Flags in richtiger Reihenfolge, Migration (vier Save-Fälle aus 8), Gustav ist nach `welcome` Einwohner ohne Werkstatt, Plan wechselt nach dem Bau.
- Eskorte: Gustav unverwundbar, Treffer löst Taumeln aus, höchstens 2 gleichzeitige Spinnen, Respawn der Spielerin führt zur korrekten Welle, Ziel liegt innerhalb des Lichts, Wellen setzen `story_hold` und geben ihn wieder frei.
- Wagen: Tür nur im Schritt `free_gustav` bedienbar, Zustand wird gespeichert, `wagon_seen` Sichtprüfung gegen Wand.
- Sichtprüfung der Position: Level 0 und erreichbar (reuse von `tools/test_*`-Mustern).
- Echtes Bild: `tools/preview_gustav_wagon.tscn -- --capture=…`.

---

## 11. Risiken und offene Entscheidungen

1. **Spinne am Tag.** Bestehende Regel: Tagesreste im Schatten, im Licht brennen sie. Der Wagenkampf bleibt im Hain; wenn der Kampf das Lichtgebiet verlässt, braucht die Spinne eine Regel (Vorschlag: sie hält sich 6 Tiles um den Wagen, `leash`). **Gegenprüfung nötig.**
2. **Eskorten-Zeit.** Die Uhr auf 0,80 zu schieben, überspringt Tageszeit. Der Zeitraffer wird als Cutscene-Konvention behandelt (wie am Hütten-Finale). Wenn sie das stört: Alternative, Eskorte nur bei `night_amount > 0,3` starten und davor eine Warte-Zeile („Sobald es dämmert, gehen wir“), kostet aber Leerlauf.
3. **NightDirector.** Er ist nach der Gründung aktiv. Er muss während Rettung/Eskorte schweigen (`story_hold`) und danach normal weiterlaufen. Ohne Prüfung könnte die erste echte Nacht mit der Eskorte kollidieren.
4. **Fluss und Gelände.** Fußweg 107 Tiles ist geprüft, Flüsse noch nicht. Zu prüfen: `data/rivers_baked.json` an der Strecke und beim Wagen (kein tiefes Wasser, Furten sind ok).
5. **Co-op.** Wie die übrigen Story-Szenen nur Host/Solo. Gustav gehört der Stadt, nicht einer Spielerin: wenn in Co-op die erste Spielerin den Quest-Stand hat, sehen alle den Zustand `residents`, aber nicht den Wagenkampf. Entscheidung offen, solange Co-op für die Story-Reihe sonst nicht gebaut ist.
6. **Kiesel-Menge.** 10 Stein aus Kieseln könnte zäh sein (6.3). Messen.
7. **Wagen-Wrack bleibt stehen.** Dauerhaft, kein späterer Zweck. Optional: Ort für späteren Fund (Ersatzteile) vormerken, nicht jetzt.
8. **Valdric fehlt bei der Rettung.** Er sieht Gustav erst am Licht. Das ist Absicht (Ellie rettet, Valdric schaut zu), schwächt aber vielleicht sein Bild als Beschützer. Alternative: er begleitet sie bis zum Rand des Suchgebiets und wartet dort.

---

## 12. Reihenfolge der Umsetzung (Vorschlag)

1. Daten: Quests, Dialogplatzhalter, `town_intro` ohne `give`, Settler-`story`-Schlüssel, `NightDirector.story_hold`.
2. Wagen-Prop und Hof (Art-Agent: `tools/art_gustav_wagon.py`), `GustavWagon`, `wagons` in `ground.json`.
3. `GustavRescueScene` (Kampf, Barks, Tür, Dialog).
4. `GustavEscortScene` mit drei Wellen und Dämmerung (Art-Agent: Clips).
5. `welcome`-Szene, Gustav als Einwohner (Lagerplan), Sichel-Gabe.
6. `town_workshop` (Task-Art `stock`, Craft-Haken, Hinweiskarte).
7. Entwickler-Sprünge, Migration, Tests, `docs/town.md` anpassen.


---

## Umsetzung (Stand 2026-11-09)

- **Quests** (`data/quests.json`): `town_start` (bis Lichtpfosten) → `gustav_rescue` (8 Schritte, Ereignisse `wagon:fight`, `wagon:meet`, `escort:gustav`, `welcome:gustav`) → `town_workshop` (`ws_gather` Material per `stock`-Aufgaben, `ws_build`, `ws_movein`, `ws_pickaxe`).
- **Wagen** `GustavWagon` (`src/entities/props/gustav_wagon.gd`, aus `data/ground.json` `wagons`, Kachel 884, 689): klopft, bis sie ihn gehört hat; die Tür lässt sich nur im Schritt `free_gustav` öffnen. Bild: `py -3 tools/art_wagon.py [preview.png]` (Ellipsoid-Renderer wie Wegweiser/Hütte: gekippter Planwagen mit gerissener, bemooster Plane, gesplittertem Bord, gebrochener Achse und liegendem Rad, Deichsel abgebrochen; zwei Frames 128×80: Tür verklemmt mit verbogenem Balken / Tür offen mit dunklem Inneren; `gustav_wagon_glow.png` mit Pilzen und violetten Adern).
- **Szenen** (Kinder des Spielers, nur solo/Host, Start über `WorldLevel.start_gustav_rescue/escort/welcome`, Neustart nach dem Laden in `resume_story`): `GustavRescueScene` (Kampf gegen die Spinne, dann Kennenlernen und Packen), `GustavEscortScene` (Eskorte mit 3 Wellen à 1/2/1 Spinnen, höchstens zwei gleichzeitig, Gustav unverwundbar, Dämmerung, `NightDirector.story_hold`), `GustavWelcomeScene` (Valdric, `gustav_welcome`: die Sichel kommt aus dem Dialog, danach `add_story_resident`).
- **Gustav** ist bis zum Einzug die Figur `StoryGustav` (Clips idle/walk/run/work); der `Settler` übernimmt sie über `takes_over: "story_gustav"`. Die Werkstatt braucht Gustav als Bewohner (`needs_resident` in `town.json`).
- **Migration** (`QuestComponent._migrate_town_start`): alte Spielstände bei `meet_stranger`/`gustav_hello` gelten als gerettet (Quest `town_workshop` wartet an `ws_pickaxe`, oder fertig bei gemachter Spitzhacke); bei `build_workshop` beginnt die Rettung (`resume_story` startet die Folgequests).
- **Dev:** STORY-SPRUNG → FERTIGE STADT steht jetzt bei `ws_pickaxe`; neu GUSTAV GERETTET (`WorldLevel.debug_jump_gustav`): Gustav am Lagerfeuer, Quest bei `ws_gather`, Sichel im Beutel.
- **Test:** `tools/test_gustav_quest.tscn` (`--fixed-fps 60`); angepasst: `test_town_story`, `test_town_jump`.
- **Platzhalter:** keine eigene Audiodatei (`tools/audio_gustav.py` fehlt), Gustav hat nur idle/walk/run/work. „Spinne greift Gustav an“ ist inszeniert (Stolpern, Hammerschwung), die Spinnen zielen nicht auf ihn. Offen: Tagspinnen-Leine/Schatten, Flüsse nahe Wagen/Weg ungeprüft, Co-op (die Szenen laufen nur solo).
