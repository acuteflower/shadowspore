# Shadowspore – HUD: Analyse und Konzept für 2.0

> **Stand:** 2026-11-24. Alle neun Schritte von Abschnitt 7 sind gebaut: Schritt 1 und die Drosselung in Abschnitt 8, die Schritte 2–9 in Abschnitt 9.
> **Gegenstand:** das Spiel-HUD (`src/ui/hud.gd`, `hud.tscn` und alle Teile, die es anlegt), seine Technik, sein Aussehen und was es für die Zonenwelt 2.0 braucht.
> **Baut auf:** `docs/v2_zonenwelt_atlas_konzept.md` (Zonen, Schwellen, Gefahrengrad, Koop Option B, Respawn-Wahl, Atlas, Chronik), `docs/design_guide.md` (Farben, Abschnitt 7), dem Rankenstil (`VineStyle`).
> **Grundlage der Sichtung:** der Code aller HUD-Teile und vorhandene Spielaufnahmen (`docs/img/fishing_night.png`). Seit Schritt 1 gibt es Aufnahmen aus der v2-Hauptwelt (`docs/img/hud_*.png`) und Messwerte pro Teil (Abschnitt 8).

---

## 0. Kurzfassung

Das HUD hat eine starke, eigene Sprache: Es gibt keine Kästen, alles wächst als Ranke vom Bildschirmrand herein, und nachts frisst die Leere die Ranken von den Spitzen her an. Diese Sprache soll bleiben.

Die Schwächen liegen woanders:

1. **Es weiß nichts von der Zonenwelt.** Es zeigt Kachelkoordinaten statt Zone und Ort. Die Questentfernung ist Luftlinie, auch wenn das Ziel hinter einer Schwelle liegt. Der Gefahrengrad ist unsichtbar. Die Todeskarte bietet keinen Wegstein an. Mitspieler in anderen Zonen sieht man nicht.
2. **Es hat keine Regie.** Wo ein Teil steht und wann er sichtbar ist, steht verstreut in `hud.tscn`, `hud.gd`, den Teilen selbst und `data/ground.json`. Fünf Mechanismen schalten unabhängig voneinander die Sichtbarkeit. Die Folge sind Überlappungen, etwa der Ortsname von `ZoneArrival` über der Koordinatenzeile der Uhr.
3. **Die Lesbarkeit leidet an den Rändern.** Ein Pixel dünne Linien und 3×5-Schrift ohne Untergrund gehen nachts und auf unruhigem Boden unter. Gamepad-Tasten werden nicht gezeigt.

Der Vorschlag hat zwei Teile. Erstens eine **HUD-Regie** (`HudDirector` + `data/hud.json`) mit festen Plätzen und Kontexten. Zweitens darauf aufbauend **sechs v2-Bausteine**: die Ortsranke, die Wegranke (Kompass und Schwellen), die zonenbewusste Questranke, die Nachtknospe (Gefahrengrad und Mond), die Gefährtenranke für Koop und die Fundranke für Chronik und Entdeckungen.

---

## 1. Bestandsaufnahme

### 1.1 Teile

Spielauflösung 640 × 360. Das `Hud` ist ein `CanvasLayer` (Ebene 1, läuft auch in der Pause).

| Teil | Datei | Platz (Bildschirm-px) | Zeigt | Angelegt in |
|---|---|---|---|---|
| `ClockVine` | clock_vine.gd | oben links, 0–172 × 8–74 | Tagesbogen mit Sonne/Mond, Uhrzeit, Tag, Tagesphase, Wetterbild, Kachel X/Y, Schlafknospe | hud.tscn |
| `PurseVine` | purse_vine.gd | oben rechts, 152 breit × 8–76 | Gold/Silber/Kupfer als Münzen an Fäden | hud.tscn |
| `QuestVine` | quest_vine.gd | rechts, 80–252 | Questtitel, Entfernung oder Suchkreis, Aufgabe, Teilaufgaben, Tafel-Aushänge | hud.gd |
| `HintCard` | hint_card.gd | links, 96–188 | Lernkarten (schleichen, Karte, fällen, bauen, schwimmen, Nebel, …) | hud.gd |
| `Hotbar` | hotbar.gd | unten Mitte, 224 breit | 8 Plätze, Stufe, EP-Licht, Einklappen nach 6,5 s | hud.tscn |
| `HealthBar` / `StaminaBar` | health_bar.gd, stamina_bar.gd (`SapVine`) | links/rechts an der Hotbar | Leben (rot, weißer Überheil-Zweig), Ausdauer (türkis) | hud.tscn |
| `BlinkIcon` | blink_icon.gd | rechts an der Hotbar | Schattenschritt-Kristall mit Abklingzeit | hud.tscn |
| `StatusTags` | status_tags.gd | über dem Lebenszweig | Zustände als Rindenpapier-Anhänger mit Restzeit | hud.gd |
| `FishingHud` | fishing_hud.gd | 30 px über der Hotbar | Tasten und Köder beim Angeln | hud.gd |
| `SpeechBox` / `BubbleRunner` | speech_box.gd, bubble_runner.gd | 64 px über dem Boden / über Köpfen | Zurufe | hud.gd |
| `DialogueBox` | dialogue_box.gd | ganzer Bildschirm | Gespräche mit Porträt | hud.gd |
| `BossBar` | boss_bar.gd | oben Mitte, 380 × 52 | Bossleben, Phasenbrüche | hud.gd |
| `MultiplayerHud` | multiplayer_hud.gd | unten links, 112 breit | Raumcode, LAN-IP, Spielerliste | hud.gd |
| Spielchat | game_chat.gd | unten links, eigener `CanvasLayer` 80 | Chat, weicht `MultiplayerHud` per Sonderfall aus | hud.gd |
| Überlagerungen | sneak_vignette, damage_vignette, wound_border, heat_haze | Vollbild | Schleichen, Treffer, Verwundung, Hitze | hud.tscn / hud.gd |
| `ZoneArrival` | zone_arrival.gd | eigener `CanvasLayer` 21 | großes Zonenschild oben, Ortsname bei (14, 66) | **`ZoneDirector`**, nicht das HUD |
| Banner | town_banner.gd (Ebene 21), mine_banner.gd (20) | oben Mitte | Stadt, Mine | jeweils eigenes System |
| `InteractPrompt` | entities/props/interact_prompt.gd | in der Welt | „E VERB“ | an jedem Objekt |

### 1.2 Bildschirmkarte heute

```
0                                   320                                  640
┌──────────────┬──────────────────────────────────────────┬──────────────┐ 0
│ ClockVine    │   BossBar / ZoneArrival / Banner          │   PurseVine  │
│  Uhr Tag     │   (alle oben Mitte, eigene Ebenen)        │              │
│  Phase X/Y   │                                           │──────────────│ 80
│ ↯Ortsname    │                                           │  QuestVine   │
│──────────────│                                           │  Titel / M   │
│ HintCard     │                                           │  Aufgabe     │
│ (96–188)     │                 Ellie                     │  Teilaufg.   │ 252
│              │                                           │              │
│              │          SpeechBox (−64)                  │              │
│ Chat         │     StatusTags   FishingHud (−30)         │              │
│ MP-Badge     │  ~~~~Leben~~~~[1][2][3][4][5][6][7][8]◆~~~Ausdauer~~~~    │ 360
└──────────────┴──────────────────────────────────────────┴──────────────┘
   ↯ = Überlappung des Ortsnamens mit der X/Y-Zeile (siehe 2.2)
```

---

## 2. Technische Analyse

### 2.1 Was gut gelöst ist

- **Neu zeichnen nur bei Bedarf.** Alle Ranken zeichnen per `_draw` Pixel für Pixel, aber gedrosselt: Uhr alle 0,18 s oder bei einem neuen Zeitschritt, Geldranke 0,16–0,35 s, Saftranken und Hotbar nur bei echter Bewegung (Dirty-Flags). Das kostet wenig.
- **Ein Wachsen für alle.** `Hud.PARTS` und `hud_reveal.gdshader` lassen jedes Teil von seiner Wurzel her einwachsen. Das ist sauber und datengetrieben.
- **Rein lokal.** Nichts im HUD sendet etwas. Es liest Komponenten (`HealthComponent`, `StatusEffects`, `QuestComponent`, `TrackedQuests`) und Autoloads.
- **Eine Gestaltungsquelle.** `VineStyle` (Farben, `leaf`, `tendril`, `infection`, `key_cap`) und `PixelText` halten die Teile zusammen.

### 2.2 Probleme

| # | Befund | Folge | Stelle |
|---|---|---|---|
| T1 | **Platz ist überall hart kodiert:** teils in `hud.tscn`, teils in `hud.gd.bind`, teils im Teil selbst (`HintCard` setzt `offset_top = 96` selbst, `ZoneArrival.PLACE_POS`, `SpeechBox.BOTTOM_GAP`, `FishingHud.RAISE`, `Hotbar.SKILL_X`). | Niemand sieht das Ganze, und neue Teile stoßen zusammen. | mehrere |
| T2 | **Überlappung Ortsname/Koordinaten:** Die X/Y-Zeile der Uhr steht bei y 62–67, der Ortsname von `ZoneArrival` bei y 66–71, beide links. Bei eingeschalteter Positionsanzeige liegen sie übereinander. | v2-Ortsnamen sind schlecht lesbar. | clock_vine.gd:250, zone_arrival.gd:26 |
| T3 | **Fünf Sichtbarkeitsregeln nebeneinander:** Leerlauf-Ausblenden (`IDLE_PARTS`), Boss (`BOSS_HIDE_PARTS`), Verdecken durch Menüs (`_cover_alpha`, nur 3 Teile), Story-Sperre (`ground.json story_start.hidden_hud`), Intro (`begin_intro`). Dazu blenden sich `SpeechBox` und `QuestVine` noch selbst aus. | Jede neue Regel braucht Code an mehreren Stellen. `ZoneArrival`, Banner und Chat hängen an keiner davon. | hud.gd |
| T4 | **v2-Teile außerhalb des HUD:** `ZoneArrival` legt der `ZoneDirector` als eigene Ebene an. Es wächst nicht mit ein, blendet im Leerlauf nicht aus und kennt die Regie nicht (es hat eine eigene Wartelogik). | doppelte Logik, eigene Ebenennummer neben `TownBanner` (beide 21) | zone_director.gd:78 |
| T5 | **Story-Sperre aus v1-Daten:** `hidden_hud` steht in `data/ground.json` (Fußpfad-Prolog). `ZoneWorld` ist keine `story_world`, also ist das HUD in v2 immer ganz offen. | Für einen v2-Prolog (WINDKAP) gibt es keinen Mechanismus, Teile zurückzuhalten. | hud.gd `_refresh_story_hud` |
| T6 | **Questentfernung ist Luftlinie** (`Interiors.travel_distance`). Liegt das Ziel in einer anderen Zone, ist die Zahl falsch, und der Weg führt vielleicht über eine ganz andere Schwelle. `MapMarkers.compute_quest_routes` berechnet die Route schon, aber nur die Karte nutzt sie. | Man läuft in den Waldgürtel statt zur Schwelle. | quest_vine.gd:223 |
| T7 | **Kachel X/Y als Ortsangabe:** Der Kommentar spricht noch von „1100 × 1100 world“, in v2 sind es Kontinentkacheln von ALTMARK (2400 × 1800). Für Spielende sagt die Zahl nichts. | Platz wird für eine Entwickleranzeige verbraucht. | clock_vine.gd:6 |
| T8 | **Todeskarte ohne v2-Entscheidung 5:** `DeathScreen.OPTIONS` = ZURÜCKKEHREN / BEENDEN. Die Wahl ZUHAUSE oder Wegstein fehlt. | Entscheidung aus dem v2-Konzept noch offen | death_screen.gd:19 |
| T9 | **Keine Gamepad-Symbole:** `VineStyle.key_name` liest nur Maus und Tastatur. `InteractPrompt` setzt beim Gamepad fest „Y“, Lernkarten zeigen Tastaturtasten. | Mit dem Gamepad stimmen die Hinweise nicht. | vine_style.gd:291 |
| T10 | **Zustände kaum unterscheidbar:** 19 Effekte in `status_effects.json`, aber nur 3 Glyphen (Flamme, Auge, Funke). Gute und schlechte Zustände sehen gleich aus, und es gibt keine Obergrenze. | Bei vielen Effekten wächst die Säule ins Bild. | status_tags.gd:151 |
| T11 | **Koop-Anzeige ist Netzwerkinfo** (Code, IP), keine Gruppenanzeige. Mitspieler haben weder Leben noch Zone. | In v2 (Spieler in verschiedenen Zonen) fehlt der Überblick. | multiplayer_hud.gd |
| T12 | **Viele Einblendungs-Systeme:** `ZoneArrival`, `TownBanner`, `MineBanner`, `HintCard.notify_*`, Beute- und EP-Texte, Bonus-Karten (`StoneReveal`, `RefineReveal`, `BrewReveal`). Es gibt keine gemeinsame Warteschlange. | Zwei Meldungen können sich gleichzeitig oben in der Mitte überlagern. | mehrere |
| T13 | **Tests hängen an v1:** `test_hotbar_fold.tscn` und `test_boss_hud_hide.tscn` laden `world_level.tscn`. Ein HUD-Bildtest für v2 fehlt. | HUD-Änderungen in v2 sind ungeprüft. | tools/ |
| T13b | **`ZoneWorld` hängt ohne `loading_in_steps`:** `_ready` läuft dann `while not loading_step(): pass` ohne Frame. `loading_step` meldet erst fertig, wenn `ZoneDirector.is_building()` falsch ist, und ein Zonenbau endet in `Jobs`-Rückrufen, die Frames brauchen. Wer die Szene nur instanziert (Tests, Vorschauen), wartet also unter Umständen ewig. Der Launcher lädt in Schritten und ist nicht betroffen. | Werkzeuge und Tests hängen | zone_world.gd `_ready` |
| T14 | **Kopplung über Konstanten:** Die Hotbar schiebt Saftranken, Kristall und Zustände über `Hud._follow_hotbar_fold` (`inset`, `drop`, `sink`). Jedes neue Teil am unteren Rand muss dort eingetragen werden. | spröde | hud.gd |

### 2.3 Kosten

Die Teile zeichnen in `_draw` mit vielen `draw_rect` von 1 px (die Uhr läuft zum Beispiel 151 Spalten ab). Durch die Drosselung ist das kein Engpass. Bevor Ranken in Texturen gebacken werden, sollte das gemessen werden: ein HUD-Profiltest misst die Zeit in `_draw` pro Teil über 600 Frames, bei Tag und bei Nacht (nachts wird mehr neu gezeichnet, wegen `infection`). Erst wenn ein Teil über ~0,3 ms liegt, lohnt sich ein Rinden-Cache (statische Rinde als `ImageTexture` pro Länge, Seed und Nachtstufe, darüber nur das Bewegte).

**Gemessen (Schritt 1, Abschnitt 8.2):** Bei Tag kostet das ganze HUD 1,2 ms pro Frame, bei Nacht 0,6 ms. Im Bosskampf mit niedrigem Leben und zwei Zuständen sind es 2,9 ms, über dem Budget von 2,5 ms. Der Engpass ist nicht die Rinde der ruhigen Ranken. Teuer sind Teile, die **jeden Frame neu zeichnen**: `BossBar`, `StatusTags`, `HintCard` und `HealthBar` bei niedrigem Leben. Dazu kommen die seltenen, aber teuren Neuzeichnungen der Hotbar (nachts 4,1 ms in einem einzigen Frame).

---

## 3. Visuelle Analyse

### 3.1 Stärken

- **Unverwechselbar:** Keine andere Oberfläche sieht so aus. Ranken, Knospen, Rindenpapier und die Leere, die nachts hineinkriecht, erzählen die Welt mit.
- **Zurückhaltend:** Leerlauf-Ausblenden, eingeklappte Hotbar und das Ausblenden im Bosskampf halten das Bild frei.
- **Einheitliche Tastenkappen** (`key_cap`) und ein durchgehendes Farbschema (Gold = Titel, Türkis = Leben und Weg, Magenta = Gefahr).

### 3.2 Schwächen

| # | Befund |
|---|---|
| V1 | **Nachtkontrast:** In `fishing_night.png` überlagern die violetten Leerenrisse am Boden die Hotbar und die Saftranken. Linien von 1 px und die Zahlen „100“ gehen darin unter. Die Leere färbt die Ranken außerdem in Töne, die denen des Bodens gleichen. |
| V2 | **Kein Untergrund:** Die Ranken haben keinen Schatten. Auf hellem Gras oder Wasser fehlt eine Kante, auf dunklem Waldboden die Helligkeit. |
| V3 | **Volle Ecke oben links:** Uhr, Tag, Phase, Wetter, X/Y, Ortsname und die Lernkarte darunter. Oben rechts: Geld und Quest. Die Mitte oben bleibt die meiste Zeit leer. |
| V4 | **Gestapelt über der Hotbar:** Zuruf (−64), Angelblatt (−30), Zustände (über Leben), dazu der Prompt in der Welt und Sprechblasen. Bei Regie-Momenten (Angeln + Zuruf + Brennen) wird es eng. |
| V5 | **Gold ist überlastet:** Questtitel, EP-Licht, Stufe, Sonne, Ortsname, Zonenname, Bossname, Geld. Wichtiges hebt sich nicht mehr ab. |
| V6 | **Kleine Schrift:** `PixelText` ist 3 × 5 px, also 10 px hoch im 2×-Fenster und 15 px bei 1080p. Für Zahlen am Rand (Leben, Ausdauer, Entfernung) ist das sehr klein, und die Beschriftung der Saftranken sinkt auf 40 % Deckkraft. |
| V7 | **Mehrere Papierkarten mit eigenen Maßen:** `HintCard`, `SpeechBox`, `StatusTags`, `ZoneArrival`-Karte und `ItemTooltip` haben ähnliches Rindenpapier, aber eigene Ränder, Deckkraft und Abstände. |

---

## 4. Konzept

### 4.1 Grundsätze

1. **Die Rankensprache bleibt.** Es kommen keine Kästen und keine Minikarte. Neues wächst vom Rand her wie das Bestehende.
2. **Feste Plätze, feste Regie.** Jedes Teil hat einen Platz (Slot) und reagiert auf Kontexte. Beides steht in Daten.
3. **Die Welt spricht, das HUD flüstert.** v2-Informationen (Zone, Ort, Schwelle) erscheinen dann, wenn sie sich ändern, und ziehen sich danach zurück.
4. **Jede Farbe hat eine Aufgabe.** Gold = Ziel und Erfolg, Türkis = Weg, Leben, Schwelle, Magenta = Gefahr, Lilienweiß = Ort und Name.

### 4.2 Die HUD-Regie (Grundlage für alles Weitere)

**`HudDirector`** (src/ui/hud_director.gd, ein Kind des `Hud`, lokal) und **`data/hud.json`**.

- **Slots** mit Anker, Versatz und Stapelrichtung: `top_left`, `top_center`, `top_right`, `right_rail`, `left_rail`, `bottom_center`, `above_bar` (gestapelt, eine Zeile pro Teil), `bottom_left`, `toast`. Ein Teil meldet sich mit `HudDirector.place(node, slot, order)` an. Die Regie rechnet die Offsets und verschiebt gestapelte Teile, wenn eines wächst oder welkt. Ersetzt die festen Werte aus T1 und den Sonderfall Chat ↔ `MultiplayerHud`.
- **Kontexte** mit Prioritäten: `explore`, `combat` (ein Schattenwesen innerhalb von 220 px), `boss`, `dialogue`, `menu`, `vista`, `build`, `fish`, `swim`, `cutscene`, `idle`. `data/hud.json` sagt pro Teil und Kontext: zeigen, dimmen (Faktor) oder verbergen. Ersetzt `IDLE_PARTS`, `BOSS_HIDE_PARTS`, `_cover_alpha` und die Selbst-Ausblendungen (T3).
- **Freischaltung** als Flag pro Teil (`unlock: "flag"`), gelesen aus `QuestComponent`. Funktioniert in v1 und v2 gleich und ersetzt `ground.json story_start.hidden_hud` (T5).
- **Ebenen:** Alles, was zum HUD gehört, kommt in den HUD-Ebenenblock (1–25). `ZoneArrival` wird ein Teil des HUD, das der `ZoneDirector` nur noch füttert (`hud.arrival.enter_zone(..)`). Die Ebenen bekommen eine Tabelle in `hud.json` (T4).
- **Hotbar-Faltung** wird zu einer Eigenschaft des Slots `bottom_center`: Was daran hängt, folgt automatisch (T14).

### 4.3 Baustein A: die Ortsranke (Zone, Ort, Gefahr) — ersetzt X/Y

Unter dem Tagesbogen der Uhr hängt statt der Koordinaten eine Zeile:

```
  ☼────────○──────────────☾
        12:40  TAG 3
       TAG  ☁
  ❧ WINDKAP · SILBERBUCHT   ◇
```

- **Zone · Ort** in Lilienweiß, der Ort nur, wenn sie in einem ist. Beim Betreten eines Ortes schreibt er sich hier ein (die Ortseinblendung von `ZoneArrival` wandert an diesen festen Platz, T2). Der Stempel ENTDECKT drückt sich rechts daneben ein.
- **Gefahrenrune ◇** rechts: RUHIG = leere Raute, RAU = halb gefüllt, WILD = gefüllt mit Dornen. Am Tag sehr blass, ab der Dämmerung (`night_amount` > 0,2) voll, weil der Grad nur nachts wirkt. Beim Überschreiten einer Schwelle in eine gefährlichere Zone pulsiert sie einmal magenta.
- **Koordinaten** gibt es nur noch als Entwickleranzeige (Einstellung POSITION, Standard aus). Sie zeigt dann Kontinent-Tile und Zonen-Tile.
- Daten: `ZoneDirector.player_zone`, `Atlas.place_at`, `Atlas.danger_scale`.

### 4.4 Baustein B: die Wegranke (Kompass und Schwellen)

Ein dünner Zweig oben in der Mitte (160 px, im heute leeren Slot `top_center`) mit Himmelsrichtungen als kleinen Knoten. Auf ihm sitzen Marken, die nach ihrer Richtung relativ zu Ellie wandern:

| Marke | Aussehen | Quelle |
|---|---|---|
| Questziel | goldene Knospe; nah = offen, fern = geschlossen | `TrackedQuests` |
| **nächste Schwelle**, wenn das Ziel in einer anderen Zone liegt | türkises Tor mit Pfeil; geschlossen = grau mit Siegel | `MapMarkers.compute_quest_routes` → `next_threshold` |
| Zuhause | kleine Hütte, nur nachts | `TownManager` / Respawn-Punkt |
| erweckter Wegstein der Zone | Statuette | `Waystones` |
| Kartenruf eines Mitspielers | Lichtstrahl, 8 s | Koop (v2 6.5) |
| eigene Pins der Zone | Pin-Glyphen | `MapMarkers.pins_for_zone` |

- Es gibt keine Entfernungen auf dem Zweig, die stehen in der Questranke.
- **Kontext:** sichtbar beim Erkunden in Bewegung. Im Kampf, im Boss, im Dialog und im Leerlauf zieht er sich zurück. In der Heimatzone innerhalb des Stadtlichts ist er gedimmt.
- Der Zweig ersetzt keinen Marker in der Welt. Er ist die schnelle Antwort auf „Wohin?“, ohne M zu drücken.
- **Entscheidung offen:** ob der Zweig dauerhaft da ist oder nur mit einer verfolgten Quest (siehe 6).

### 4.5 Baustein C: die Questranke wird zonenbewusst

- Liegt das Ziel in der eigenen Zone: wie heute „TITEL · 84 M“, aber mit der **Wegstrecke**, wenn eine Route bekannt ist.
- Liegt es in einer anderen Zone, zeigt die erste Zeile unter dem Titel das nächste Stück der Route:
  `→ KRONENGANG · 120 M` und klein darunter `DANN ERLENFURT`.
  Die Entfernung gilt bis zur Schwelle. Nach dem Übertritt springt die Zeile zum nächsten Stück, und die Knospe blüht kurz auf.
- **Geschlossene Schwelle:** `→ KRONENGANG (VERSPERRT)` in Grau, darunter der `closed_reason` aus dem Atlas.
- **Suchkreis** bleibt, wird aber auch über Zonen hinweg so behandelt (erst zur Schwelle, dann „SUCHKREIS 40 M“).
- Daten: `QuestComponent.current()` + `MapMarkers.compute_quest_routes`. Neu ist ein kleiner reiner Helfer `QuestRoute` (src/systems), den Karte, Wegranke und Questranke gemeinsam nutzen, damit alle drei dasselbe sagen.

### 4.6 Baustein D: die Nachtknospe

Die Schwierigkeit steigt in v2 mit der Nacht, dem Mond und dem Gefahrengrad. Das soll man vor der Nacht sehen, nicht erst wenn es zu spät ist.

- Am rechten Ende des Tagesbogens sitzt eine **Mondknospe**, die die Mondphase zeigt (`TimeManager.moon_phase()`: Neumond dunkel mit magenta Rand = härter, Vollmond hell = milder).
- **Sondernächte** (Flut, Stille, Sturm, Nebel) zeigen ab der Dämmerung ein kleines Omen an der Knospe. Der Text dazu kommt wie heute über die Ansage in der Dämmerung.
- Ab der Dämmerung wächst aus der Knospe ein **Dornenzweig**, dessen Länge Mond × Gefahrengrad der Zone zeigt. Keine Zahl, nur ein Gefühl. In der Heimatzone kommt ein kleines Stadtsymbol dazu, wenn Raids möglich sind (Stadt gegründet und ein Spieler in der Heimatzone, v2 6.6; eine Abfrage dafür gibt es in `ZoneWorld` noch nicht).
- Die Schlafknospe der Uhr bleibt.

### 4.7 Baustein E: die Gefährtenranke (Koop, Option B)

Ersetzt das Netzwerk-Abzeichen unten links durch eine Gruppenanzeige am linken Rand (`left_rail`, unter der Lernkarte):

```
 ◆ MIRA      ~~~~~~      ← Mitspieler in derselben Zone: Lebenssaft
 ◆ JONAS     ERLENFURT   ← in einer anderen Zone: Zonenname statt Saft
 ◆ KAI       ✝ 0:12      ← tot: Wiederkehr
```

- Pro Mitspieler: Spore in der Spielerfarbe (`PLAYER_TONES`), Name, und entweder ein kurzer Lebenssaft (gleiche Zone) oder der Zonenname. Ein Zustandssymbol, wenn jemand brennt, vergiftet oder bewusstlos ist.
- **Raumcode und IP** wandern in die Seitenleiste des Pausemenüs (`PauseSocialSidebar` gibt es schon). Beim Hosten erscheinen sie einmal als Fundmeldung.
- Ein Spieler in einem Kampf oder Boss blinkt leise magenta. Ein Klick auf der Karte zeigt „ZU IHM“ (v2 6.5), im HUD gibt es keinen Knopf.
- Leben der Mitspieler: Es wird schon repliziert (`HealthComponent` sendet an alle Peers). Für Spieler in anderen Zonen braucht es nur die Zone (`player_zone`).

### 4.8 Baustein F: die Fundranke (Meldungen)

Eine gemeinsame Warteschlange für alles, was sich als Meldung kurz einblendet (T12):

| Rang | Beispiele | Form |
|---|---|---|
| **groß** | erste Ankunft in einer Zone, Stadt gegründet, Siegel, Kontinentebene freigeschaltet | das große Schild oben Mitte (heute `ZoneArrival`/`TownBanner`) |
| **mittel** | Ort entdeckt, Wegstein erweckt, Schleierfaden x/8, Chronik 30/60/100 %, Aussichtspunkt | ein Blatt am rechten Rand unter der Questranke, das herabschwingt und welkt |
| **klein** | Beute, Geschenk eines Haustiers, Tafelaushang, Gefahrengrad gewechselt | eine Zeile in der Ortsranke oder über der Hotbar |

- Regeln: Es gibt nur eine Meldung pro Rang gleichzeitig. Große Meldungen warten auf Kampf-, Dialog- und Story-Ende (die Wartelogik von `ZoneArrival` wird hier allgemein). Gleiche kleine Meldungen werden zusammengefasst („+3 TANNENHOLZ“).
- **Schleierfäden** bekommen ihre eigene mittlere Meldung: Ein Faden zieht sich vom Fundort über den Bildschirm in die Questranke, darunter „SCHLEIERFADEN 3/8 · WINDKAP“.
- API: `HudDirector.notify(rank, id, data)`. Banner und Karten melden sich dort an, statt eigene Ebenen zu öffnen.

### 4.9 Baustein G: Todeskarte v2

Entscheidung 5 aus dem v2-Konzept: Nach dem Prolog bietet die Todeskarte **ZUHAUSE** und, wenn in der aktuellen Zone ein Wegstein erweckt ist, **WEGSTEIN · NAME**.

- Unter den Wahlmöglichkeiten zeigt ein kleiner Ausschnitt der Zonenkarte (aus `AtlasView`, Ebene ZONE) beide Punkte und den Ort des Todes.
- Die Wahl geht als Parameter an `Player.request_respawn(target)`. Der Host prüft sie über `respawn_point_for(peer, target)`, das es in `ZoneWorld` schon gibt.

### 4.10 Lesbarkeit und Zugänglichkeit

- **Tintenschatten (V1, V2):** Jede Ranke bekommt unter Text und Zahlen einen 1 px breiten, geditherten Schatten in `1b1a2e` mit 55 % Deckkraft (über `VineStyle`, ein Schalter für alle). Nachts hält die Leerenfärbung 3 px Abstand zu Zahlen und Knospen.
- **HUD-Kontrast** (Einstellung, Standard mittel): steuert die Stärke der nächtlichen Leere auf den Ranken und den Tintenschatten.
- **Großschrift** (Einstellung): Eine zweite `PixelText`-Größe (5 × 7) für Zahlen und Namen am Rand (Leben, Ausdauer, Entfernung, Ort, Uhrzeit). Der Rest bleibt 3 × 5. Die Plätze der Regie wachsen mit.
- **Saftranken-Werte** nicht unter 70 % Deckkraft sinken lassen (heute 40 %).
- **Gamepad-Kappen (T9):** `VineStyle.key_name` liest auch `InputEventJoypadButton`/`Motion` und gibt Kürzel zurück, die `key_cap` als runde Knöpfe zeichnet (A B X Y in der Form, LB RB als flache Kappe, Sticks als Kreis mit Pfeil). Welches Gerät gilt, sagt `InputManager.using_mouse`. Das betrifft `InteractPrompt`, `HintCard`, `FishingHud`, `BlinkIcon` und die Todeskarte.
- **Zustände (T10):** Glyphe pro Effekt aus `status_effects.json` (`glyph`). Gutes hängt an einem türkisen Blatt, Schlechtes an einem magenta Dorn. Höchstens 4 Anhänger, dazu „+N“.

### 4.11 Zonenstimmung im HUD (klein, optional)

`ZoneMood.now` färbt das HUD leicht mit: ein Uniform `g_hud_tint` (höchstens 12 % Mischung) auf die Rinde der Ranken. Im Hexenwald wird die Rinde moosig-dunkel, an der Küste salzgrau, in Leerenzonen kommt die nächtliche Leere auch am Tag ein wenig hervor. Text, Zahlen und Gefahrenfarben bleiben unberührt.

---

## 5. Neue Bildschirmkarte

```
0                                   320                                  640
┌──────────────┬──────────────────────────────────────────┬──────────────┐ 0
│ ☼──○────☾◐   │   N ───◇────▲────────○─── O               │   PurseVine  │  ← Wegranke (B)
│ 12:40 TAG 3  │   (Boss: BossBar · groß: Schild)          │──────────────│
│ ❧WINDKAP·    │                                           │  QuestVine   │
│  SILBERBUCHT◇│                                           │  → KRONENGANG│
│──────────────│                                           │    120 M     │
│ HintCard     │                                           │──────────────│
│──────────────│                 Ellie                     │  Fundblatt   │  ← mittlere Meldung (F)
│ ◆ MIRA ~~~   │                                           │              │
│ ◆ JONAS ERL. │        [above_bar: Zuruf / Angeln /       │              │
│              │         Zustände, gestapelt]              │              │
│ Chat         │  ~~~~Leben~~~~[1][2][3][4][5][6][7][8]◆~~~Ausdauer~~~~    │ 360
└──────────────┴──────────────────────────────────────────┴──────────────┘
```

Oben links: Uhr mit Mondknospe (D) und Ortsranke (A). Links: Lernkarte, darunter die Gefährtenranke (E). Oben Mitte: die Wegranke (B), im Bosskampf von der `BossBar` abgelöst. Rechts: Geld, Questranke (C), Fundblatt (F). Unten Mitte: wie heute, aber alles darüber gestapelt von der Regie.

---

## 6. Offene Entscheidungen

| # | Frage | Vorschlag |
|---|---|---|
| 1 | Wegranke dauerhaft oder nur mit verfolgter Quest? | Dauerhaft beim Erkunden in Bewegung, im Leerlauf weg. |
| 2 | Koordinaten ganz aus dem Spiel? | Ja, nur noch als Entwickleranzeige (Standard aus). |
| 3 | Gefahrengrad am Tag zeigen? | Blass am Tag, voll ab der Dämmerung. |
| 4 | Gefährtenranke links oder rechts? | Links (rechts ist mit Geld, Quest und Fundblatt voll). |
| 5 | Großschrift als Option oder Standard? | Option, Standard aus. Prüfen, sobald der Bildtest läuft. |
| 6 | Zonentönung des HUD (4.11)? | Ja, aber zuletzt und abschaltbar. |

---

## 7. Bau-Reihenfolge

| Schritt | Inhalt | Prüfung |
|---|---|---|
| **1. Sehen und messen** | Aufnahmewerkzeug `tools/preview_hud.tscn` für die v2-Hauptwelt (Tag, Nacht, verwundet, eingeklappt, Angeln, Boss, Koop-Attrappe). Klären, warum die Szene nach dem Laden hängt. HUD-Profiltest (2.3). `test_hotbar_fold` und `test_boss_hud_hide` auf `ZoneWorld` umstellen. | Bilder in `docs/img/hud_*.png`, Messwerte pro Teil |
| **2. Regie** | `HudDirector`, `data/hud.json` (Slots, Kontexte, Freischaltung, Ebenen). Alle bestehenden Teile umziehen, ohne dass sich ihr Aussehen ändert. `ZoneArrival` in das HUD. | `tools/test_hud_layout.tscn`: keine zwei sichtbaren Teile überlappen sich in 12 Kontexten; Bildvergleich vorher und nachher |
| **3. Ortsranke + Nachtknospe** (A, D) | Zone, Ort, Gefahrenrune, Mondknospe, Dornenzweig. X/Y als Entwickleranzeige. | Schwelle im Labor überschreiten, Mondphasen 0/4 |
| **4. Wegranke + zonenbewusste Questranke** (B, C) | `QuestRoute`-Helfer, Marken, Schwellen-Text, geschlossene Schwellen | Ziel in Nachbarzone: Ranke zeigt die Schwelle, Entfernung fällt bis zur Schwelle |
| **5. Fundranke** (F) | Warteschlange, drei Ränge, Banner umziehen, Schleierfaden-Meldung | Fünf Meldungen gleichzeitig: keine Überlagerung, richtige Reihenfolge |
| **6. Todeskarte v2** (G) | ZUHAUSE / WEGSTEIN mit Kartenausschnitt, `request_respawn(target)` | Host lehnt einen Wegstein ohne Erweckung ab |
| **7. Gefährtenranke** (E) | Gruppenanzeige, Code/IP in die Seitenleiste | Zwei-Prozess-Test: Mitspieler in anderer Zone zeigt den Zonennamen |
| **8. Lesbarkeit** | Tintenschatten, HUD-Kontrast, Großschrift, Gamepad-Kappen, Zustände mit Glyphen und Obergrenze | Bildtest Nacht auf Leerenrissen; Gamepad-Bild aller Kappen |
| **9. Zonentönung** (optional) | `g_hud_tint` aus `ZoneMood` | Hexenwald/Küste nebeneinander |

Die Schritte 3–8 hängen nur von Schritt 2 ab und können danach in beliebiger Reihenfolge gebaut werden. Schritt 4 braucht `MapMarkers` (gibt es), Schritt 6 die Wegsteine in v2 (Atlas-Schritt 10).

---

## 8. Schritt 1: gebaut (2026-11-24)

### 8.1 Werkzeuge

| Werkzeug | Aufruf | Was es tut |
|---|---|---|
| `tools/hud_test_world.gd` | `HudTestWorld.open(self)` (preload) | Lädt die v2-Hauptwelt (`ZoneWorld`) **in Schritten** wie der `GameLauncher` (`loading_in_steps`, dann init/step/warmup je ein Frame). Gruppe `sandbox`, nichts wird gespeichert. Gibt den lokalen Player zurück, sobald sein HUD steht, schaltet das HUD frei (`hud_unlocked`) und öffnet es. Grundlage aller HUD-Tests. |
| `tools/preview_hud.tscn` | `Godot --rendering-driver opengl3 --path . tools/preview_hud.tscn -- --dir=/abs [--only=day,night,..] [--x2]` | Acht Szenen: `day`, `night`, `dusk`, `wounded` (5 % Leben, Brennen, Schattengift, Ausgeruht), `folded` (eingeklappte Hotbar), `fishing` (Rute in der Hand), `boss` (Bossleiste MORNATH), `arrival` (erster Eintritt in die Zone + Ort mit ENTDECKT). Werkzeuge, Beeren, Geld und eine Quest werden vorher gegeben. Ohne Grafik (headless) läuft es durch, speichert aber nichts. |
| `tools/test_hud_profile.tscn` | `Godot --headless --path . tools/test_hud_profile.tscn [-- --out=/abs.json]` | Kosten pro HUD-Teil (Methode im Kopf des Skripts): `_process` über eigene `process_priority`-Plätze zwischen Messknoten, `_draw` über aufgeschobene Klammern um ein erzwungenes `queue_redraw`, die natürliche Neuzeichnungsrate über das `draw`-Signal. Szenen `day`, `night`, `busy`. Schlägt fehl, wenn das HUD mehr als 2,5 ms pro Frame kostet; Teile über 0,3 ms stehen als WARN da. **Schlägt heute in `busy` fehl** (2,9 ms), siehe 8.2. Das ist der erste echte Befund und kein Fehler des Tests. |
| `test_hotbar_fold`, `test_boss_hud_hide` | wie bisher | laufen jetzt in `ZoneWorld` statt in `WorldLevel`. Beide bestehen (`HOTBAR FOLD OK`, `TEST BOSS HUD HIDE: PASS`). `test_boss_hud_hide` hatte einen alten Parse-Fehler (`set_flag` mit zwei Argumenten), der ist behoben. |

**Warum die Szene hing (T13b):** `ZoneWorld._ready` lädt ohne `loading_in_steps` in einer Schleife ohne Frame, der Zonenbau braucht aber `Jobs`-Rückrufe, die nur zwischen Frames kommen. `HudTestWorld` lädt deshalb in Schritten. Zweite Falle: Ohne Grafik (headless) kommt `RenderingServer.frame_post_draw` nie. Ein `await` darauf hängt für immer. Aufnahmen werden deshalb headless übersprungen.

**Dritte Falle (Testaufbau):** Brennen oder Gift bei 5 % Leben töten Ellie. Der Tod löst die Rettung durch die Göttin aus (`GoddessSystem._on_story_ward`, Sternenhalle, Dialog), und die folgenden Aufnahmen landen in der Sternenhalle. Die Szenen mit wenig Leben setzen deshalb `health.floor_value = 1`, denn `can_rescue` überspringt Spieler mit Untergrenze.

### 8.2 Messwerte (headless, GDScript-Kosten, Mikrosekunden)

`cost` = Prozess pro Frame + ein Neuzeichnen × Neuzeichnungen pro Frame. `draw` = Kosten **eines** Neuzeichnens.

| Teil | Tag: draw / pro s / cost | Nacht: draw / pro s / cost | Busy: draw / pro s / cost |
|---|---|---|---|
| Hotbar | 1104 / 2,9 / 126 | **4100** / 0,9 / 130 | 3842 / 1,3 / 144 |
| HintCard (Lernkarte sichtbar) | 545 / **60** / **596** | – / 0 / 62 | – / 0 / 54 |
| BossBar | – | – | **3497** / 21,5 / **1392** |
| StatusTags | – | – | 495 / **60** / 520 |
| HealthBar | 278 / 13,8 / 76 | 329 / 0,3 / 15 | 277 / **60** / 289 |
| StaminaBar | 242 / 13,8 / 72 | 282 / 0,3 / 19 | 250 / 21,5 / 107 |
| ClockVine | 415 / 5,5 / 42 | 430 / 6,3 / 49 | 366 / 9,0 / 59 |
| QuestVine | 261 / 6,5 / 34 | 320 / 7,0 / 44 | 307 / 10,0 / 57 |
| PurseVine | 235 / 2,8 / 24 | 329 / 7,0 / 53 | 290 / 10,3 / 63 |
| ZoneArrival (leer) | 39 / **60** / 70 | 10 / **60** / 40 | 9 / **60** / 37 |
| Hud (`hud.gd._process`) | 68 | 77 | 63 |
| 14 geschlossene Fenster (nur `_process`) | zusammen ~110 | ~120 | ~110 |
| **Summe** | **1229** | **630** | **2914 (über Budget)** |

Was daraus folgt:

1. **Jeden Frame neu zeichnen ist das eigentliche Problem.** `HintCard` (`queue_redraw()` am Ende jedes `_process`), `StatusTags` und `HealthBar` bei Wunde zeichnen mit 60/s, `BossBar` mit ~21/s. Eine Drosselung auf 20 Bilder pro Sekunde (wie bei den ruhigen Ranken) halbiert bis drittelt ihre Kosten, ohne dass man es sieht.
2. **Die Bossleiste ist das teuerste Teil** (3,5 ms pro Bild). Eine gebackene, zackige Grundlinie, über die nur Puls und Geist gezeichnet werden, wäre der erste sinnvolle Cache.
3. **Die Hotbar ruckelt nachts in Einzelframes:** Sie zeichnet selten neu, dann aber 4,1 ms lang (Leerenbefall über die ganze Ranke). Das ist der Fall für den Rinden-Cache aus 2.3 (statische Ranke als Textur pro Nachtstufe).
4. **`ZoneArrival` zeichnet auch leer 60-mal pro Sekunde.** Das ist billig (10–40 µs), sollte aber in Schritt 2 (Umzug ins HUD) verschwinden.
5. **Geschlossene Fenster** kosten zusammen ~0,1 ms pro Frame nur durch `_process`. Sie sollten `set_process(false)` setzen, solange sie zu sind.

### 8.3 Befunde aus den Aufnahmen

| Bild | Befund |
|---|---|
| `hud_day.png`, `hud_arrival.png` | **T2 bestätigt:** „DIE SILBERBUCHT · ENTDECKT“ liegt auf der X/Y-Zeile der Uhr. |
| `hud_day.png`, `hud_folded.png` | **V2 bestätigt:** Auf hellem Gras sind Slotnummern, die Zahlen „100“ der Saftranken und die 1-px-Ranke kaum zu lesen. Die Leerlauf-Äste von Uhr und Quest ziehen als lange leere Linien über das Bild. |
| alle | **T6/v1-Ziel:** Die Quest „DIE HOLZFÄLLERHÜTTE · SUCHKREIS 40 M“ zeigt in Windkap auf ein v1-Ziel. Die Questranke weiß nichts von Zonen (Baustein C). |
| `hud_night.png` | Nachts ist der Kontrast der Ranken gut. Die Leere frisst die Ranke sichtbar an. |
| `hud_wounded.png` | Wundrand, Zustandsschilder (VERBRENNEN, SCHATTENGIFT, AUSGERUHT) und Schadenszahlen sind sauber. Die Schilder sitzen links über der Hotbar und sind gut lesbar; die Lebenszahl ist bei 5 % kaum zu finden. |
| `hud_fishing.png` | Das Angelblatt sitzt mittig über der Hotbar, die Tastenkappen folgen der deutschen Belegung (Y/H). |
| `hud_boss.png` | Uhr, Geld und Quest verschwinden wie vorgesehen. Die Bossleiste steht frei oben in der Mitte. |
| `hud_arrival.png` | Zonenkarte (WINDKAP, Umriss mit Eintrittspunkt) oben mittig: gut. Der Ort links überdeckt X/Y (siehe T2). |


### 8.4 Drosselung (gebaut) und Messung nach allen Schritten

`BossBar`, `StatusTags`, `HintCard` und die Saftranken zeichnen höchstens 20-mal pro Sekunde neu statt in jedem Frame (im Kampf oder bei Bewegung schneller, wo es auffiele). `ZoneArrival` zeichnet nur noch, solange es etwas zeigt.

Gemessen nach allen neun Schritten, mit Wegranke, Gefährtenranke, Fundranke und Ortsranke (`test_hud_profile`, headless):

| Szene | Vorher (8.2) | Jetzt | Budget |
|---|---|---|---|
| Tag | 1229 µs | 1468 µs | 2500 µs |
| Nacht | 630 µs | 981 µs | 2500 µs |
| Busy (Boss, Wunde, Zustände) | **2914 µs** (über Budget) | 1680 µs | 2500 µs |

Die neuen Teile kosten am Tag und in der Nacht zusammen etwa 0,25–0,35 ms. Busy liegt jetzt deutlich unter dem Budget.

---

## 9. Schritte 2–9: gebaut (2026-11-24)

Alle Teile sind lokal und rein kosmetisch. Die einzige Ausnahme ist die Respawn-Wahl der Todeskarte: Über sie entscheidet der Host.

| Schritt | Gebaut | Dateien |
|---|---|---|
| **2. Regie** | `HudDirector` (Kind `Director` des `Hud`) liest `data/hud.json`. Dort stehen die Ebenen (`hud` 1, `mine_banner` 20, `town_banner` 21, `notices` 22, `death` 60, `chat` 80), die 12 Kontexte (idle, vista, boss, menu, dialogue, cutscene, combat, build, fish, swim, notice, town) mit Ein- und Ausblendzeiten, die Slots und für jedes Teil Slot, Reihenfolge, Box, Kontext-Faktoren und `unlock`-Flag (das frühere `hidden_hud` aus ground.json). Der Stapel-Slot `above_bar` hebt Teile übereinander, statt sie zu überdecken; Teile, die relativ zeichnen, lesen `hud_lift`. `hud_busy()` und `hud_height` sagen der Regie, ob und wie hoch ein Teil gerade da ist. `ZoneArrival` liegt auf der Ebene `notices`, Orte gehen an die Ortsranke. | `src/ui/hud_director.gd`, `data/hud.json`, `src/ui/zone_arrival.gd` |
| **3. Ortsranke + Nachtknospe** (A, D) | Unter der Uhr: Rune (Raute RUHIG / RAU / WILD, pulsiert ab der Dämmerung), dann ZONE · ORT. Ein Ort tippt sich mit einem Glimmen ein, beim ersten Besuch mit dem Stempel ENTDECKT. Ein Wechsel des Gefahrengrads gibt eine kleine Meldung. Am Ende des Uhrbogens sitzt die Nachtknospe: eine Scheibe der Mondphase (Neumond mit magentafarbenem Rand), ein Auge bei einer Sondernacht (`NightDirector.tonight_special()`) und ein Dornenzweig. Der Zweig wächst mit Dämmerung und Gefahrengrad und wird im Licht der Stadt halb so lang. X/Y gibt es nur noch als Entwickleranzeige (Einstellung POSITION (ENTWICKLER), Standard aus) als „K x,y  Z x,y“ (Kontinent- und Zonenkachel). | `src/ui/clock_vine.gd`, `src/world/night_director.gd` |
| **4. Wegranke + zonenbewusste Questranke** (B, C) | `QuestRoute.plan` (rein) gibt für ein Ziel in einer anderen Zone die nächste Schwelle, die Zone danach, die Meter bis zur Schwelle und den Fall „versperrt“ mit dem Grund der ersten geschlossenen Schwelle. Die Questranke zeigt darüber „→ ZONE · N M“ und darunter „DANN …“ oder den Grund. Die Wegranke ist ein Kompasszweig oben in der Mitte (±90° um die Laufrichtung, Knoten N/O/S/W). Ihre Marken: die Quest-Knospe (offen ab 320 px), die Schwelle (türkis, oder grau mit Siegel), nachts das Zuhause, der erweckte Wegstein der Zone, Kartennadeln und Koop-Pings (8 s). Liegt eine Marke hinter Ellie, zeigt sie einen halben Pfeil. | `src/systems/quest_route.gd`, `src/ui/way_vine.gd`, `src/ui/quest_vine.gd`, `ZoneDirector.flags()` |
| **5. Fundranke** (F) | `HudNotices` mit drei Rängen. **Groß:** eine Bühne für Stadt-, Minen- und Zonenbanner (`claim_big` / `release_big`, gesperrt im Kampf, Banner warten in einer Reihe). **Mittel:** ein Papierblatt rechts über der Leiste (Wegstein erweckt, Schleierfaden x / 8, Aussicht, Chronik 30/60/100 %). **Klein:** eine Zeile über der Leiste (Beute +N, zusammengefasst nach Gegenstand; neuer Aushang; Hort-Fund des Gefährten). Gleiche Meldungen werden zusammengefasst. In den ersten 3 s nach dem Laden zählt nichts. | `src/ui/hud_notices.gd`, `town_banner.gd`, `mine_banner.gd`, `vistas.gd`, `pet_registry.gd` |
| **6. Todeskarte v2** (G) | Die Karte zeigt einen Ausschnitt der Zone mit Umriss, Kreuz am Todesort, Wegstein und Zuhause. Die Wahl schickt `Player.request_respawn(target)`, der Host prüft sie mit `world.respawn_allowed`. Ein Wegstein muss erweckt sein und in derselben Zone liegen, ZUHAUSE geht immer. Ziel ist die Stadttür, solange es keine Stadt gibt das Küstenlager. Der Teleport auf der Client-Seite entfällt. | `src/ui/death_screen.gd`, `player.gd`, `zone_world.gd` |
| **7. Gefährtenranke** (E) | Links unter der Lernkarte stehen bis zu 3 Mitspieler. Jede Zeile hat eine Spore in der Spielerfarbe und den Namen. Danach folgt entweder eine Saftlinie (gleiche Zone), „→ ZONE“ (andere Zone) oder „✝ s“ (gefallen), dazu die Marken Schwimmen, Raum oder Mine. Ein magentafarbenes Blinken zeigt einen Kampf: eine Schattenkreatur in 220 px Nähe oder eine laufende Bossleiste. `MultiplayerHud` ist anfangs eingeklappt. | `src/ui/companion_vine.gd`, `multiplayer_hud.gd` |
| **8. Lesbarkeit** | `HudText`: ein Tintenschatten `1b1a2e` zu 55 %. Mit HUD-KONTRAST sind es 85 % und ein Rand. Mit GROSSE SCHRIFT wird eine 5×7-Schrift statt 3×5 verwendet. `HudText.ink` ersetzt `PixelText.draw` in Quest, Geld, Hotbar, Saftranken, Zuständen, Lernkarte und Uhr. Die Saftzahlen ruhen bei 72 % statt 40 %. Mit Gamepad liefert `VineStyle.key_name` „@A“ und Ähnliches: runde farbige A/B/X/Y, flache LB/RB/LT/RT, Sticks als Ring. Wer Tasten als Wort schreibt, übergibt `pad = false` oder nutzt `key_text`. Bei den Zuständen gibt es höchstens 4 Schilder, der Rest wird zu „+N“. Gute Zustände tragen ein türkises Blatt, schlechte einen magentafarbenen Dorn (`good` in data/status_effects.json). Drei Schalter auf der Einstellungsseite. | `src/ui/hud_text.gd`, `vine_style.gd`, `status_tags.gd`, `game_settings.gd`, `pause_menu.gd` |
| **9. Zonentönung** | Statt eines Shader-Globals `g_hud_tint` (alles HUD wird auf der CPU gezeichnet) sind die Rindenfarben von `VineStyle` statische Variablen (`BARK*`, Grundwerte in `BASE_BARK*`). `VineStyle.follow_mood` neigt sie zur Farbe der Zone, viermal pro Sekunde aus der Regie heraus, höchstens 12 % (`TINT_MAX`). Die Stimmungsprofile haben dafür drei neue Schlüssel: `hud_bark` (Farbe), `hud_tint` (0..1) und `hud_void` (0..1, wie viel der nächtlichen Leere auch am Tag durchscheint). Belegt sind Küste und Landzunge (salzgrau), tiefer Wald (moosgrün), Hexenwaldrand (moosig-dunkel), Glaskamm (kühles Grau) und Leerenriss (violett, mit Leere). Text, Zahlen, Blätter und Gefahrenfarben bleiben, wie sie sind. Abschaltbar mit ZONEN-TÖNUNG. | `vine_style.gd`, `zone_mood.gd`, `data/world/moods.json`, `hud_director.gd` |

**Test:** `tools/test_hud_layout.tscn` (headless, `HUD LAYOUT OK`). Er prüft 468 Dinge:

- In 12 erzwungenen Kontexten überlappen sich keine zwei sichtbaren Teile, außer Teilen derselben Anhängegruppe.
- Beute-Meldungen werden zusammengefasst, und die Bühne für große Meldungen lässt sich korrekt belegen und freigeben.
- `QuestRoute`: Ein Ziel in ERLENFURT ist ohne Flags VERSPERRT, mit allen Flags offen und hat dann eine Entfernung; ein Ziel in derselben Zone braucht keinen Weg.
- Ortsranke: Ort, Stempel und Gefahrengrad.
- Zonentönung: Sie wirkt, bleibt unter der Obergrenze und lässt sich zurückschalten.
- Respawn: Zuhause ist immer erlaubt, ein unbekannter Wegstein wird abgelehnt.
- Mehr als vier Zustände führen zu Schildern mit „+N“.

**Nicht gebaut:**

- Rinden-Cache der Hotbar pro Nachtstufe (8.2, Punkt 3) und eine gebackene Grundlinie der Bossleiste (8.2, Punkt 2).
- Code/IP der Sitzung in der Seitenleiste der Gefährtenranke.
- Ein Bildvergleich vorher/nachher als automatischer Test (die Aufnahmen werden von Hand angesehen).
