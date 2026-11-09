# Shadowspore – Hauptmenü (Konzept)

Status: **Entscheidung: „Lager + Cursor-Licht" (A + B). Erste Stufe gebaut** (siehe Abschnitt 0); der Rest ist Konzept (Entscheidungen am Ende, Abschnitt 11).

## 0. Was gebaut ist (erste Stufe)

- **Router:** `GameLauncher` (`src/world/game_launcher.gd`) startet jedes Spiel: Modi `continue`, `new`, `host`, `join` (mit `address`, `port`). `main.gd` zeigt ohne Argumente das Menü; Dev-Flags (`--host`, `--join`, `--new`, `--arena`, `--skip-intro`, `--skip-menu`) starten wie bisher direkt, `--menu` erzwingt das Menü. Das Menü und „Neu beginnen" im Pausenmenü legen die Anfrage in `GameLauncher.pending` und laden `main.tscn` neu (`GameLauncher.launch` setzt Pause, Zeitlupe, `InputManager`-Sperren und `Terrain.relief` zurück). Die Weltszenen werden dort per `load()` geholt (ein `preload` macht einen Zirkelbezug).
- **Kulisse:** `MainMenu` (`src/ui/main_menu.gd`) rendert die echte Welt ohne Spieler (`menu_world.gd` setzt `_spawn_player` außer Kraft; nur per Laufzeit-`load` und Duck-Typing, ein Parse-Bezug auf `WorldLevel` macht einen Zirkelbezug) bei Nacht am Feuerplatz der renovierten Hütte, Uhr fest auf 0.88. Darüber `menu_dark.gdshader` (Dunkel kriecht von den Rändern, Feuer und Cursor halten Lichtkreise offen, Klick lässt ihn aufflackern; ohne Maus wandert das Licht zum gewählten Eintrag), das Logo (`TitleLogo.play_build`, Klick/Taste überspringt) und die Oberfläche.
- **Oberfläche:** `MainMenuUi` (`src/ui/main_menu_ui.gd`): fünf Namensschilder an einer Ranke (WEITER nur mit Spielstand, NEUES SPIEL, MEHRSPIELER, EINSTELLUNGEN, BEENDEN), Karten für Überschreib-Nachfrage, Mehrspieler (Hosten / Beitreten mit tippbarer Adresse `ip[:port]`, Strg+V) und Einstellungen (Schieberegler per Klick oder ←/→, Schalter). Maus, Tastatur (Pfeile, Enter/Leer/E, Esc) und Gamepad (`ui_*`).
- **Prüfen:** `tools/test_main_menu.tscn` (headless: Seiten, Adresse, NEUES SPIEL startet wirklich eine Welt mit Spieler), `tools/preview_main_menu.tscn -- --dir=/abs [--times=2,5,9] [--page=settings|multi|join|confirm] [--mouse=x,y]`.
- **Noch nicht:** Spielstand-Slots (`SPIELSTÄNDE`), Einträge als Objekte im Lager (Deckel, Bank, Wegweiser …), Rand-Augen im Dunkel, Postkarte des Spiels, Ton/Musik, Verbindungsprüfung beim Beitreten (`join` meldet nur, ob der Client angelegt wurde), „Zum Hauptmenü" im Pausenmenü, Option für reduzierte Bewegung.
Bezug: Logo und Titelkarte in [logo_title_concept.md](logo_title_concept.md) (Logo, Aufbau und Idle sind fertig), Look in [design_guide.md](design_guide.md).

---

## 1. Ausgangslage (was es schon gibt)

| Baustein | Stand |
|---|---|
| `main.tscn` / `main.gd` | startet **ohne Menü** direkt in die Welt: ohne Argument Singleplayer (Save laden, sonst Intro), `--host`, `--join[=ip]`, `--arena`, `--new`, `--skip-intro` |
| Logo | `TitleLogo`, 440 × 240 px (in 640 × 360 also fast der ganze Bildschirm), Aufbau ca. 6,2 s (`play_build`, `skip_build`), Idle-Leben, eigene Echtzeituhr; `TitleCard` zeigt es schon über einem Nachthimmel (`title_backdrop.gdshader`) |
| Netzwerk | `NetworkManager.host_singleplayer / host_multiplayer(port) / join(address, port) / leave()`, Port 7777, max. 4 Spieler. `join` meldet nur, ob der Client **angelegt** wurde; ob die Verbindung klappt, kommt später (`connected_to_server` / `connection_failed`) |
| Speichern | **ein** Slot (`user://save.json`), `SaveGame.info()` kennt nur Zeitpunkt, Tag, Uhrzeit. `save/load_into/delete` nehmen aber schon einen `path` an |
| Einstellungen | `GameSettings` (Lautstärke, Vollbild, VSync, Wackeln, Zahlen, Position, Cursor; Sprache und Musik nur gespeichert). Die Zeilen stehen heute **im** `PauseMenu` (Reiter EINSTELLUNGEN) |
| UI-Sprache | `VineStyle` (Ranken aus dem Bildrand), `PixelText`, Schlüsselkappen `key_cap`, `GameCursor`, Rindenpapier-Karten (`paper`), Halte-zum-Bestätigen (Fortschrittsfenster) |
| Weltbausteine | echte Welt auch ohne Spielerin renderbar (`tools/preview_daylight.gd`: `WorldLevel` ohne Spieler + `Camera2D`), `DayNight`, `Fireflies`, Wind, Wildtiere, Hütte mit Hof, Feuerstelle, Sitzplätze, Laterne, Wegweiser, Kanaldeckel, Wegstein, Weltrand der Leere, Ellie-Sitzanimation mit Tasse, Valdrics Sitzclips |
| Audio | Tag-/Nacht-Ambience, viele Foleys; **keine Musik** (Regler existiert, es gibt aber keine Stücke) |

Fazit: Fast **alles Sichtbare für ein lebendiges Menü existiert schon**. Neu zu bauen sind vor allem Ablauf, Spielstand-Metadaten, Mehrspieler-Formulare und die Choreografie.

---

## 2. Gewünschte Funktionen

SPIEL STARTEN (neu) · SPIELSTAND LADEN · MEHRSPIELER (hosten, beitreten) · EINSTELLUNGEN · SPIEL BEENDEN.
Dazu sinnvoll: **WEITER** (letzter Stand, ein Klick), Sammlungen (Flussbuch, Kochbuch) als Extra, und der Rückweg „zum Hauptmenü" aus dem Pausemenü.

Der Anspruch: das Menü soll **leben, einladen, überraschen** – nicht nur Knöpfe vor einem Bild.

---

## 3. Das Kernproblem: das Logo ist groß

440 × 240 von 640 × 360 lässt unten nur **ca. 120 px**. Ein Pixel-Logo wird nicht skaliert. Lösungen:

1. **Logo oben, Szene unten** (Empfehlung): das Logo hängt wie ein Schild im Nachthimmel; die untere Bildhälfte ist eine Szene, **die Menüeinträge sind Dinge in dieser Szene** (Abschnitt 4 A). Nach dem Aufbau darf das Logo 20–40 px nach oben rutschen (unten bleibt Platz für Beschriftungen).
2. **Logo links, Ranken rechts**: Logo oben links, die Einträge hängen als Ranke vom rechten Rand (wie die Fußleiste des Pausemenüs). Platz rechts: 640 − 440 = 200 px.
3. **Zwei Zustände**: Titelbild (Logo mittig, „E DRÜCKEN") → das Logo weicht (wird von der Leere nach oben „weggeschoben" bzw. verkleinert nicht, sondern schiebt sich halb aus dem Bild) → Menü. Alles bleibt pixelecht.

Skizze zu 1 (Maße im 640 × 360-Bild):

```
 +----------------------------------------------------------------+
 |   *     .          Sterne, Mond (Phase = Spieltag)       .      |
 |            +-----------------------------------+                |
 |            |   S H A D O W     (Logo 440x240)  |                |
 |            |      S P O R E                    |                |
 |            +-----------------------------------+                |
 |  ~~~ Baumlinie, Nebel, ferne Leere am Rand ~~~~~~~~~~~~~~~~~~~~ |
 |  [Deckel]  [Hütte]   [Feuer + Ellie/Valdric]  [Laterne] [Wegw.] [Rand] |
 |  NEUES     WEITER      (Spielstände)         MEHRSPIELER EINSTELL. ENDE |
 +----------------------------------------------------------------+
```

---

## 4. Leitideen (fünf Richtungen, kombinierbar)

### A. „Das Lager" – die Menüeinträge sind Dinge im Lager *(Empfehlung als Grundgerüst)*

Die Szene ist Valdrics Hof bei der Hütte, **Dämmerung/Nacht**, Feuer brennt, Wind, Glühwürmchen. Ellie sitzt am Feuer (vorhandene Sitzanimation mit Tasse, zufällige Gesten alle 5–10 s), Valdric sitzt gegenüber. Jeder Eintrag ist ein Ding:

| Eintrag | Ding in der Szene | Hover / Auswahl |
|---|---|---|
| **NEUES SPIEL** | der **Kanaldeckel** (der Anfang der Geschichte) | Deckel ruckelt, von unten **klopft** es (`knock.wav` aus dem Intro), ein violetter Riss leuchtet |
| **WEITER** | die **Hütte**, Tür auf, warmes Fenster | Licht fällt heraus, Beschriftung zeigt „TAG 12 · STADT …" |
| **SPIELSTÄNDE** | der **Hocker/Stumpf am Feuer** oder ein Beet daneben (siehe Idee F) | Kamera schwenkt zum Beet |
| **MEHRSPIELER** | die **Stadtlaterne** (Licht ist Land): Laterne anzünden = hosten, dem Licht folgen = beitreten | Laterne flackert, Licht wächst |
| **EINSTELLUNGEN** | der **Wegweiser** (Bretter drehen sich) oder Gustavs Werkbank | Bretter klappern |
| **SPIEL BEENDEN** | der **Rand der Leere** im Dunkeln hinter dem Lager | siehe „Abschied" (Abschnitt 6) |

Warum: erzählt die Welt schon vor dem ersten Schritt, jeder Eintrag ist ein kleines Erlebnis, alle Bilder existieren. Mit Maus (Hover/Klick), Tastatur (W/S bzw. A/D, E, Esc) und Controller (Stick, A/B) bedienbar; **jedes Ding trägt immer eine kleine Beschriftungsfahne** (VineStyle-Blatt mit Schlüsselkappe), damit nichts geraten werden muss.

### B. „Die Spore" – ein lebendiger Begleiter statt Mauszeiger

Das Spor-O verlässt das Logo und wird zum **Wesen unter dem Cursor**: ein leuchtendes Sporenlicht, dem Glühwürmchen und Sporen folgen. Wo es hinfliegt, wächst Licht („Licht ist Land"): Einträge sind **Blüten an Ranken** (BloomOrb: Knospe → halb → offen), die aufgehen, wenn die Spore nahe kommt. Unbeleuchtetes ist dunkel und lässt Augenpaare sehen.
Die reine UI-Variante, günstig, passt zur HUD-Sprache. Gut als **Cursor-Verhalten in A** statt als eigene Szene.

### C. „Die Postkarte deines Spiels" – das Menü zeigt DEIN Spiel *(stärkster persönlicher Effekt)*

Der Hintergrund ist **kein fester Ort, sondern der Zustand des gewählten Spielstands**: dort steht deine Stadt (Häuser, Lampen, Zäune, Trampelwege), es ist die gespeicherte Uhrzeit und Mondphase, Bewohner leben ihren Plan, nachts glimmt das Licht. **Neues Spiel** zeigt die unberührte Wiese mit dem Deckel. Fährt man über eine Spielstand-Karte, **schwenkt die Kamera** zu diesem Stand und blendet in dessen Welt über. Technik: `TownManager.import_state` am Menü-Level wie in `preview_daylight --town`; sonst als Vorschau-Bild, das beim Speichern mitgeschrieben wird (siehe 7).

### D. „Die Karte" – Menü als Weltkarte im Nebel

Vollbild-Karte wie `MapWindow` (Schattennebel mit Ranken, Augenpaare bei Nacht): Spielstände sind **beleuchtete Ausschnitte** (die gespeicherte Entdeckung `"map"` ist schon im Save), Einträge sind Wegzeichen. Hübsch für die Slot-Anzeige, als ganzes Menü aber statischer und weniger „lebendig". Wir nehmen davon die **Slot-Karten mit Nebel-Miniatur**.

### E. „Das Erwachen" – filmisches Menü / Attract-Mode

Nach ca. 45 s ohne Eingabe fährt die Kamera selbstständig kurze **Vignetten** ab (je 8–12 s): Gustav hackt Holz, Valdric übt mit dem Schwert, ein Fuchs schnüffelt am Vorratsstapel, Raben auf dem Dach, die Leere beißt am Weltrand, Mornath zieht als Silhouette über den Mond, ein Reiher am Fluss. Jede Eingabe bringt das Menü zurück. Ein Baustein, den man **später aufstockt** (jede Vignette ist ein kleines, abgeschlossenes Stück).

> **Empfohlener Mix:** A als Grundgerüst, B als Cursor-Verhalten, C für die Karten (mit D als Miniatur), E später als Dauerbonus.

---

## 5. Interaktive Bausteine („Spielzeug" im Menü)

Alle rein kosmetisch, ohne Auswirkung auf Spielstände. Auswahl, nicht alles muss rein:

1. **Licht ist Land im Menü:** der Cursor trägt ein kleines Licht. Dunkelheit schiebt sich vom Bildrand herein (`VineStyle.infection`); im Licht ist man sicher. Beschriftungen erscheinen nur im Licht.
2. **Augen im Dunkeln:** Paare magentafarbener Augen am Rand blicken zum Cursor, weichen aus dem Licht zurück, blinzeln weg. Bleibt man über 40 s ohne Eingabe, rücken sie ein Stück näher – nie ganz.
3. **Das Logo anfassen:** Klick auf das Auge im SHADOW-O → es blickt dem Cursor nach und zwinkert; Klick auf die Laterne im SPORE-O → sie flackert (das Lagerlicht mit); Klick auf die Sporenblume → Sporenstoß; die Adern pulsieren schneller, wo der Cursor ist.
4. **Wildtiere reagieren auf Mausgeschwindigkeit:** langsam = schleichen (Kaninchen grasen weiter), schnell/Klickerei = Lärm (sie flüchten, Raben fliegen auf). Das übt die Schleichmechanik nebenbei.
5. **Glühwürmchen fangen:** Klick fängt eins, es leuchtet im Cursor und wird mit Rechtsklick freigelassen.
6. **Tageszeit-Perle:** die Uhrenranke (`ClockVine`) ist verschiebbar – man dreht Tag und Nacht des Menüs selbst. Standard: das Menü läuft einen **12-Minuten-Tag** (`TimeManager`) und beginnt beim ersten Start in der Dämmerung. Einstellbar: „wie im Spiel / echte Uhr / immer Nacht".
7. **Mond und Wetter:** Mondphase = (Anzahl Menüstarts) mod 8 oder der Spieltag des gewählten Standes; selten Regen mit Pfützenringen, Windböen mit Blättern, eine Sternschnuppe (Klick = Wunsch, nichts passiert; ein Funke).
8. **Figuren reagieren:** Hover über NEUES SPIEL – Valdric blickt zum Deckel; Hover über BEENDEN – er winkt (Platzhaltertext „SCHON MÜDE?"). Ellie schaut dem Cursor nach (wie im Inventar).
9. **Verstecktes:** fünf Leuchtkappen im Bild finden (Klick = Puls) schaltet **Menü-Varianten** frei (Morgenstimmung, Blütenwetter, Mondfinsternis) – nur Kosmetik. 7× auf SHADOW klicken: eine Spinne krabbelt über das Logo. Auf dem Deckel „klopfen" (Klick-Rhythmus) lässt es antworten.
10. **Mehrspieler-Moment:** ein beitretender Spieler setzt sich ans Feuer (siehe Lobby, Abschnitt 6).

---

## 6. Ablauf und Seiten

```
START → (Aufbau des Logos, 6,2 s, jede Taste überspringt) → HAUPT
HAUPT ─ NEUES SPIEL ─→ Slot wählen (leer / überschreiben mit Halten) ─→ START
      ─ WEITER ───────────────────────────────────────────────────→ START
      ─ SPIELSTÄNDE ─→ Slot-Beet (laden, löschen mit Halten E)
      ─ MEHRSPIELER ─→ HOSTEN | BEITRETEN
      ─ EINSTELLUNGEN ─→ dieselben Zeilen wie im Pausemenü
      ─ SAMMLUNGEN (optional) ─→ Flussbuch, Kochbuch (lesen)
      ─ BEENDEN ─→ Abschied
```

- **Start eines Spiels:** Neues Spiel → die Kamera fährt in den Deckel hinab, Schwarz, Intro (Klopfen). Weiter → Türiris (`door_wipe.gdshader`) schließt auf der Hütte, im Dunkeln streamt die Welt, ein Blatt zeigt den **letzten Auftrag** („DIE HÜTTE ERNEUERN") und einen Spieltipp („LICHT IST LAND"), die Iris öffnet sich bei Ellie. Laden wird so zur Inszenierung.
- **Slot-Beet (SPIELSTÄNDE):** drei Beete. Leer = Erde mit Samen. Belegt = **eine Pflanze, die mit dem Fortschritt wächst** (Spross → junge Pflanze → Blüte → Baum, nach Stufe/Stadtgröße/Boss). Hover = Rindenpapier-Karte (Stadtname, Tag, Stufe, Spielzeit, Auftrag, „vor 2 Tagen"), plus kleine **Nebel-Miniatur** der Karte (Idee D) bzw. Vorschaubild. E lädt. Löschen: **E halten**, die Pflanze welkt zu Sporen. Beschädigte Datei: Pflanze ist grau, Hinweis statt Absturz.
- **MEHRSPIELER hosten:** Slot oder neu, Spielerzahl 2–4, Port (Standard 7777), eigene Adresse(n) anzeigen (`IP.get_local_addresses()`) mit „KOPIEREN". Die Laterne wird angezündet; auf dem Feld steht, wer schon da ist.
- **Beitreten:** Adresse[:Port], Liste der **zuletzt benutzten** (`user://recent_hosts.json`), Verbinden mit sichtbarem Zustand („LICHT WIRD GESUCHT …" mit flackernder Laterne), Zeitlimit (~8 s), Fehler in der Spielsprache („KEIN LICHT AN DIESER ADRESSE", „DAS LAGER IST VOLL", „ANDERE VERSION"). Optional **LAN-Laternen** (Abschnitt 7): gefundene Spiele erscheinen als kleine Laternen am Horizont, ein Klick tritt bei.
- **Lobby am Feuer *(größerer Ausbau)*:** wer verbunden ist, **setzt sich** an einen der Sitzplätze (Stumpf, Baumstamm, …) mit der Farbe/dem Namen; der Host startet, wenn alle da sind. Setzt voraus, dass Verbindung und Spielstart getrennt werden (heute passiert beides beim Betreten der Welt) – eigener Schritt.
- **Abschied (BEENDEN):** Halten bestätigt (kein versehentliches Beenden): das Feuer sinkt, die Leere frisst den Bildrand (Biss-Shader der Todesanzeige in sanft), Klang klingt aus, dann Schluss. Mit ungespeicherter Welt gibt es das nicht – das Menü kennt nur Zustände ohne laufendes Spiel.
- **Rückweg:** Pausemenü bekommt **ZUM HAUPTMENÜ** (speichern + zurück). Pflicht: danach sauberer Zustand (siehe Risiken).
- **Eingaben:** Maus, Tastatur (ui_*-Aktionen wie im Pausemenü), Controller; Schlüsselkappen zeigen die gebundene Taste, bei Controller „Y/A/B". Zurück = Esc/B.

---

## 7. Technik (Vorschlag)

**Struktur**
- `main.tscn` wird zum **Router**: ohne Argument → `MainMenu`; mit den Entwickler-Argumenten (`--host`, `--join`, `--new`, `--arena`, …) wie bisher direkt ins Spiel. Dazu ein Argument/Schalter **`--skip-menu`** (und `--menu` zum Erzwingen), damit die Entwicklungsschleife im Editor nicht länger wird.
- `MainMenu` (`src/ui/main_menu/main_menu.gd`) mit Zuständen BOOT → LOGO → HAUPT → SEITE → START; eine Seite pro Klasse (`MenuSlots`, `MenuHost`, `MenuJoin`, `MenuSettings`). Zeiten und Texte in `data/main_menu.json`.
- Die Starthandlung (aus der heutigen `main.gd`) wandert in eine kleine Funktion `GameLauncher.start(mode, slot, address)`; Menü und Entwicklerargumente rufen dieselbe.

**Hintergrund – drei Stufen** (Messung entscheidet, siehe Risiken)
1. *Leicht:* eigene `MenuStage` aus echten Bausteinen (Boden der Umgebung, Hütte, Hof, Feuer, Bäume, `DayNight`, Wind, Glühwürmchen, eine Handvoll Kaninchen/Raben) in einem Ausschnitt, ohne Streaming.
2. *Echt:* `WorldLevel` ohne Spielerin (`EmptyWorld` wie in `preview_daylight.gd`) plus Kamera am Hof. Maximal lebendig und gratis aktuell, aber schwerer; beim Start eines Spiels wird dieses Level **abgebaut** und frisch gebaut (oder bei „Neues Spiel" weiterverwendet, falls es unberührt ist).
3. *Postkarte (Idee C):* Stufe 2 + `TownManager.import_state` aus dem gewählten Slot.

**Spielstand-Metadaten** (`SaveGame`, `VERSION` 2, alte Saves bleiben lesbar und zählen als Slot 1)
- Slots: `user://save.json` (Slot 1, unverändert), `save_2.json`, `save_3.json`; `SaveGame.slots()` liefert pro Slot `info()`.
- Neu in `info()`: `level`, `playtime`, `town_name`, `quest_title`, `explored` (Prozent aus `MapDiscovery`), `moon`, `thumb` (kleines Vorschaubild 160 × 90 als `save_N.png` neben der Datei). Beim Speichern mitgeschrieben, ohne die Datei zu laden (kleiner `"meta"`-Block, damit `info()` nicht den ganzen Save parst).
- Sicherheit: erst in `.tmp` schreiben und umbenennen, dazu `.bak` des letzten guten Stands (löst auch das „halbe Datei"-Risiko).
- Mehrspieler-Saves: heute lädt `main.gd` nur im Solo; ob der Host Spielstände laden/speichern soll, ist **offen** (Abschnitt 11).

**Netzwerk**
- `NetworkManager.join_async(address, port, timeout)` mit Signalen `connecting`, `connected`, `failed(reason)` (Zeitlimit, Fehlerarten wie „voll", „Version"), damit das Menü Rückmeldung geben kann. Versionscheck über die Spielversion beim Handshake.
- Adressen in `user://recent_hosts.json` (max. 8). **LAN-Suche** (optional): Host sendet alle 1–2 s ein UDP-Broadcast-Paket (`PacketPeerUDP`, Port 17777) mit Name, Spielerzahl, Version; das Menü hört mit.
- Vor Sologame vom Menü aus: `leave()` aufräumen; ein lokaler Host im Hintergrund darf nicht auf 7777 lauschen.

**Einstellungen:** nicht kopieren. Die Zeilen aus `PauseMenu._build_items("settings")` in eine gemeinsame Klasse (`SettingsPage`) ziehen; Pausemenü und Hauptmenü nutzen sie. (Refactor mit Regressionstest: Reglerwerte, Rückkehr zur Taste, Speichern.)

**Audio:** `tools/audio_menu.py` (synthetisierte Platzhalter): Hover, Klick, Zurück, Karten-Entfalten, Laterne anzünden, Deckel-Klopfen, Beet-Welken, Feuer-Ausklingen. **Musik** gibt es noch keine: Vorschlag eine leise, lange Schleife (Drone + wenige Töne), im Menü stärker, im Spiel nicht – eigener Schritt und eigene Entscheidung.

**Wiederverwendung:** `TitleLogo` (Idle und Aufbau, Kurzfassung ab 3,0 s bei jedem späteren Menü), `VineStyle`/`PixelText`/`key_cap`, `GameCursor` (Hot-Hints), `BoardWindow`-Stil für die Karten, `ItemTooltip`-Stil für Spielstandkarten, `BloomOrb` für die Blüten, `door_wipe` und `interior_dark` für Übergänge, `Fireflies`, `WorldWind`, `DayNight`.

**Neue Kunst** (nur Kunst, vom `gpt-6.1-terra`-Agent laut CLAUDE.md): Beetpflanzen in 4 Wachstumsstufen × 3 Arten, eine kleine Fern-Laterne (LAN), evtl. ein Beet-Sockel, Augen-Sprites für den Rand (aus bestehendem Auge ableitbar). Figuren, Hütte, Feuer, Laterne, Wegweiser, Deckel gibt es.

**Tests:** `tools/test_main_menu.tscn` (Zustandsautomat, Zurück/Esc überall, Slot-Metadaten, Löschen mit Halten, Join-Zeitlimit und Fehlertexte, kein Rest nach Start/Rückkehr, Eingabegeräte), `tools/preview_main_menu.tscn -- --capture=/abs/ordner [--t=…] [--state=…]` für Bildfolgen, Netztest in zwei Prozessen (neuer Loopback-Port, z. B. 17904).

---

## 8. Abfolge in Schritten

1. **Router & Gerüst:** `GameLauncher`, `MainMenu` mit Logo auf Nachthimmel, Hauptliste (WEITER, NEU, LADEN, MEHRSPIELER, EINSTELLUNGEN, BEENDEN) in Ranken-Optik, Tastatur/Maus/Controller, `--skip-menu`. *(Ergebnis: vollständig bedienbares, noch schlichtes Menü.)*
2. **Spielstände:** Slots, Metadaten, `.bak`, Karten, Löschen mit Halten; Vorschaubild.
3. **Einstellungen teilen:** `SettingsPage` aus dem Pausemenü ziehen, Hauptmenü nutzt sie.
4. **Mehrspieler:** `join_async`, Fehlertexte, zuletzt benutzt, Host-Formular mit Adresse/Kopieren.
5. **Szene (Idee A):** `MenuStage` mit Hof, Feuer, Ellie/Valdric, Dinge als Einträge, Beschriftungsfahnen, Übergänge (Deckel, Türiris).
6. **Lebendigkeit:** Cursor-Licht, Augen, Logo-Klicks, Wildtiere, Tageszeit-Perle, Mond.
7. **Pausemenü → HAUPTMENÜ**, sauberer Zustand, Test.
8. **Später:** Postkarte (C), Slot-Beet mit wachsenden Pflanzen, LAN-Laternen, Lobby am Feuer, Attract-Mode (E), Verstecktes, Musik.

Jeder Schritt ist für sich spielbar; Schritt 1–4 ist das **Mindestmenü**, ab 5 wird es besonders.

---

## 9. Risiken und Messpunkte

- **Aufräumen beim Zurückkehren:** viele Autoloads haben Zustand (`TimeManager.locked`, `Engine.time_scale`, `GameCursor`-Looks, `InputManager`-Sperren, `Jobs`-Warteschlange, laufende Szenen wie `AmbushScene`, Tweens). Ein Test muss „Spiel → Menü → Spiel" mehrfach prüfen. Wenn es zu fragil wird, ist die sichere Notlösung: Zurück zum Menü = **Neustart des Prozesses** (Spiel wird mit `--menu` neu gestartet).
- **Kosten der Hintergrundwelt:** Stufe 2 ruft Chunk-Streaming, Wildtiere, Nachtlogik. Messen (Frametime im Leerlauf, Speicher), Ziel: Menü im Leerlauf deutlich unter dem Spielbudget, Notausgang Stufe 1.
- **Verbindung:** `create_client` gelingt auch bei falscher Adresse; echte Fehlermeldung nur über Signale/Zeitlimit.
- **Versionen:** Client und Host mit verschiedener Version brauchen eine klare Meldung statt verwirrender Fehler.
- **Beschädigte Saves:** nie Absturz, nie stilles Überschreiben (`.bak`, `.tmp`).
- **Bewegung/Blitzen:** Option „ruhiges Menü" (keine Glitches, keine Partikel, Kamera still; deckt sich mit der offenen „reduzierte Bewegung" aus dem Logo-Konzept). Keine Vollbild-Blitze; Biss und Glitch nur gedämpft.
- **Zu viele Ideen:** jedes Spielzeug aus Abschnitt 5 ist ein eigener kleiner Baustein mit eigenem Schalter in `data/main_menu.json`.

---

## 10. Erste Texte (Platzhalter)

WEITER · NEUES SPIEL · SPIELSTÄNDE · MEHRSPIELER · EINSTELLUNGEN · SAMMLUNGEN · BEENDEN · „LICHT ANZÜNDEN" (hosten) · „DEM LICHT FOLGEN" (beitreten) · „LICHT WIRD GESUCHT …" · „KEIN LICHT AN DIESER ADRESSE" · „DAS LAGER IST VOLL" · „ANDERE VERSION" · „HALTEN ZUM LÖSCHEN" · „SCHON MÜDE?" (Valdric). Alles Platzhalter, Dialogtexte schreibt der Dialog-Agent.

---

## 11. Entscheidungen

| Frage | Empfehlung |
|---|---|
| Leitidee | **A (Lager) als Gerüst**, B als Cursor-Verhalten, C/D für Spielstandkarten, E später |
| Logo-Anordnung | Logo oben, Szene unten; nach dem Aufbau 20–40 px höher |
| Hintergrund | erst Stufe 1 (`MenuStage`), nach Messung Stufe 2/3 |
| Spielstand-Slots | 3 Slots, alter Save = Slot 1, Wachstums-Beet später |
| Mehrspieler-Spielstände | **offen:** darf der Host laden/speichern oder nur neue Welten? |
| LAN-Suche | später, optional |
| Lobby am Feuer | später, nach Trennung von Verbindung und Spielstart |
| Musik im Menü | eigenes Thema, eigener Schritt (heute keine Musik im Spiel) |
| Rückweg ins Menü | Pausemenü „ZUM HAUPTMENÜ", Notlösung Prozess-Neustart |
| Entwickler | `--skip-menu` plus Schalter in den Einstellungen |
| Verstecktes/Freischaltbares | nur Kosmetik des Menüs |
| Sprache | Deutsch, Texte als Platzhalter |
