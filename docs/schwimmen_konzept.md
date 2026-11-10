# Schwimmen an der Oberfläche – Konzept

Stand: 2026-11-09. **Nur Konzept, nichts gebaut.** Umfang: Ellie schwimmt auf der Wasseroberfläche von Flüssen und Seen (`WorldRivers`), mit Sprint für schnelleres Schwimmen. Tauchen, Unterwasserwelt, Ertrinken, Strömungsmitreißen, Boote und Schwimmen für Tiere sind ausdrücklich **nicht** Teil davon.

## 1. Ausgangslage (was es schon gibt)

- `WorldRivers.surface_at` / `wade_data` liefern aus dem Wasserfeld (`field_at`: x = Abstand zum Ufer, y = Tiefe) `shallow_water` / `deep_water`, plus `submerge` (1–6 px, `river_life.json`) und `speed` (0,94 → 0,66). Das Waten ist fertig: `WaterOverlay` (flaches Wasserrechteck über den Beinen), `_sink`, Plätscher an den Fußkontakten (`_on_step`, `WaterRipples`).
- **Tiefes Wasser (`field.y > deep_threshold` 0,64) ist heute eine Wand:** `RiverDepth` (`StaticBody2D` je Wasserchunk, offline zusammengeführte Rechtecke, Layer 1) und `terrain.json` `deep_water` (`speed 0.5`, `allow_sprint false`, `allow_blink false`). Furten sind die einzigen Übergänge. Gegner-Navigation lehnt tiefes Wasser ab. „Es gibt weiterhin kein Schwimmen“ (`docs/map_and_lakes.md`).
- Der Spieler hat Laufen (`max_speed` 62 px/s), Sprint (`sprint_speed` 104, Stamina 12/s), Schleichen (42) und Blinzeln. Körperblätter sind 8 Richtungen × Clips (`_use_sheet` 0–12), gebaut mit `tools/art_hero3d.py` (Ellipsoid-Renderer, Pose-Schlüssel `pitch`, `shift`, `dy`, `leg_angles`, `both_arms`, `droop`, …), dazu Blut-Schwellkarten, Rig-Daten (`hero_rig.json`) und Schmuck-Punkte (`hero_jewelry.json`).
- `Player._surface` wird auf **jedem Peer** aus der Position berechnet (nicht nur beim Besitzer). Das ist die Grundlage dafür, dass Schwimmen ohne eigenes Netzprotokoll für die Bewegung auskommt.

## 2. Leitidee

Schwimmen soll sich wie ein **eigener, ruhiger Bewegungsmodus** anfühlen, nicht wie langsames Laufen: Sie liegt im Wasser, die Beine arbeiten unter der Oberfläche, die Arme tauchen ein und aus, vor ihr schiebt sich eine kleine Bugwelle, hinter ihr zieht ein Kielwasser. Sprint ist kein „schneller Laufen“, sondern ein **Wechsel der Technik** (Brust → Kraul). Wichtig ist, dass man die Technik am Bild erkennt, ohne UI.

Wasser ist dabei **Gelände mit Regeln**, kein Strafraum: Schwimmen ist langsamer als Laufen, aber nie hilflos; es öffnet Abkürzungen und Ufer, die vorher nur über Furten zu erreichen waren.

## 3. Zustände

```
LAND ─ WATEN ─┬─ ABSTOSSEN ─► WASSERTRETEN ◄──► BRUST ◄──► KRAUL
              │                    ▲              ▲          ▲
              └─ KOPFSPRUNG ───────┴──────────────┴──────────┘ (nur aus Sprint)
   ▲                  │
   └── AUFSTEHEN ◄────┘  (Füße finden Grund)
```

| Zustand | Wann | Bewegung |
|---|---|---|
| `WATEN` | bestehend; flaches Wasser (`amount` < `swim_enter`) | unverändert (`wade_data`) |
| `ABSTOSSEN` | Übergang Waten → Schwimmen | 0,35 s, Steuerung bleibt, Tempo blendet auf Schwimmtempo |
| `WASSERTRETEN` | im Tiefen, keine Eingabe | steht auf der Stelle, leichtes Auf-und-Ab, optional leichte Strömungsdrift |
| `BRUST` | Eingabe, kein Sprint | **Schwimmtempo 34 px/s** (≈ 0,55 × Gehen) |
| `KRAUL` | Eingabe + Sprint, Stamina > 0 | **Sprintschwimmen 58 px/s** (≈ 0,93 × Gehen, schneller als Waten durch tiefes Wasser) |
| `AUFSTEHEN` | Tiefe sinkt unter `swim_exit` | 0,3 s, Beine setzen auf, geht ins Waten über |
| `KOPFSPRUNG` | Sprint (≥ Jogtempo) in tiefes Wasser | 0,7 s: Sprung (≈ 22 px Bogen, kein Gelände-Blocken), Eintauchen, Auftauchen in `BRUST`/`WASSERTRETEN` |

Alle Zahlen stehen in einer neuen `data/swim.json` (siehe 9), nichts im Skript.

**Hysterese:** Eintritt, wenn `amount` ≥ 0,92 (kurz vor der heutigen Wand), Austritt erst unter 0,80. Keine Zustandswechsel mehr, wenn sie auf der Grenze „wackelt“ (zusätzlich Mindestdauer 0,25 s je Zustand).

**Nicht erlaubt im Wasser** (`allow_*` in `terrain.json`, wie bei `deep_water` schon vorgesehen): Blinzeln, Schleichen, Schwert/Werkzeug ziehen und schwingen (Waffe wird weggesteckt wie beim Schleichen, `AttackComponent.sheathed`), Wuchtschlag, Essen, Pflücken, Angeln, Bauen, Angriffe der Waffenklassen. **Erlaubt:** Inventar, Karte, Dialoge, Interagieren mit Wasserpflanzen im Reichweitenradius (`WaterPlantCut` per E, ohne Pflückanimation: Hand streckt sich, nur Effekt), Trinken später.

## 4. Spielregeln

### 4.1 Stamina
- Brust: −4/s (Regeneration pausiert, aber kein Verbrauch im Wassertreten: +3/s).
- Kraul: −14/s (mehr als Sprint an Land, 12/s), nur solange Stamina > 0.
- **Erschöpft** (Stamina 0): Kraul endet, Brust geht auf 0,7 × Tempo (24 px/s) bis Stamina wieder > 10 %. **Kein Ertrinken, kein Lebensverlust.** Das Wasser bestraft Gier mit Langsamkeit, nicht mit Tod (Oberfläche-nur-Prinzip).

### 4.2 Verwundet und Story
- Verwundet (≤ 10 % HP): Schwimmen erlaubt, nur Brust, ×`WOUND_SPEED`. Im Prolog fließt kein Wasser durch den Pfad, daher kein Konflikt; geprüft werden muss die Story trotzdem (Hüttenhof, Steinbruch): `swim_allowed()` ist falsch bei `story_lock`, `intro`, in Innenräumen (`Interiors.slot_at`) und in der Mine.
- Kein Schwimmen in Void-Wasser (Karte: „Binnenwasser ist Leere“); nur Flächen von `WorldRivers`.

### 4.3 Kollision (der heikle Punkt)
`RiverDepth` blockiert heute alles auf Layer 1. Nur der **Spieler** darf durch, Tiere, Gegner und Navigation nicht. Empfehlung:

- `RiverDepth` bekommt die Gruppe `river_depth`. Solange `swim_allowed()`, ruft der lokale Spieler `add_collision_exception_with(body)` für jeden geladenen `RiverDepth`-Körper in Reichweite (Chunk-Attach meldet neue Körper über ein Signal `depth_attached(body)` von `WorldRivers`); beim Entladen räumt Godot freigegebene Körper selbst aus der Liste, `swim_allowed()` → falsch entfernt alle (gleiches Muster wie die Spinnen-Kletterausnahmen: „Temporary collision exceptions are removed on landing…“).
- Verworfen: `RiverDepth` auf einen neuen Layer 8 legen und überall Masken erweitern (zu viele Berührungspunkte: Tiere, Navigation, Projektile, Mine).
- Die Ufer-/Reliefwände (`relief_walls`) und die Weltleere blockieren weiter. Wasserfälle: das Backen erzeugt keine automatischen (`docs/rivers_world.md`); falls später welche existieren, bekommt der Fall eine eigene Sperre.
- **Gegner:** Spinnen, Zuhörer, Brecher kommen nicht ins tiefe Wasser (Navigation lehnt es ab). Deshalb ist tiefes Wasser ein **Zufluchtsort vor Nahkämpfern**. Das ist beabsichtigt als erste Fassung (offene Frage in 11).
- **Nacht:** `NightDirector` zählt schwimmende Spieler normal; Lockung (Lärm) beim Kraulen: Planschgeräusch zählt als Sprint-Lärm ×1,0, Brust ×0,5, Wassertreten ×0,2.

### 4.4 Strömung (optional, Stufe 2)
`field_at` liefert Fließrichtung (`BA`). Im Wassertreten und bei Brust wirkt **höchstens 18 % von `max_speed`** als Drift in Fließrichtung, gegen den Strom bremst Brust um bis zu 15 %. Nie so stark, dass man nicht ankommt; Fische/Angeln nutzen schon `FishingComponent.current_at` (Schwäche am Ufer, volle Stärke im Fahrwasser) – dieselbe Funktion wiederverwenden.

### 4.5 Multiplayer
- Zustand und Technik sind eine **kleine synchronisierte Eigenschaft** `swim` (0 = nicht, 1 = Tread, 2 = Brust, 3 = Kraul) im `MultiplayerSynchronizer` des Spielers (wie `sprinting`). Der Besitzer entscheidet (Position, Eingabe, Stamina), der Host validiert Stamina über die bestehende `StaminaComponent`.
- Übergangs-Clips laufen als **reliable RPC** `_play_swim_transition(kind, dir)` über denselben Weg wie `_begin_action` / `_play_action` (`Player._busy`, `_busy_kind`, `_busy_time`) – alle Peers sehen Einstieg, Kopfsprung und Ausstieg gleich; Bewegungszyklen sind aus `swim` + Geschwindigkeit abgeleitet (kein Paket je Frame).
- Späte Beitritte: `swim` steht im Synchronizer-Zustand, der Zyklus startet im richtigen Clip.

## 5. Animationen (Körper)

Alles mit dem vorhandenen Renderer (`tools/art_hero3d.py` `build()`), **kein** neues Verfahren: Ellipsoid-Modell, 8 Blickrichtungen echt gerendert, dieselbe Kleidung, Haar und Mantelschöße, nass nachgedunkelt. Neues Skript `tools/art_hero_swim.py` (Muster: `art_hero_fish.py`, `art_hero_carry.py`), Blatt `assets/characters/player_swim.png` als **Blatt 13** in `Player._use_sheet`. Aufruf und Kontaktbögen wie bei den anderen: `py -3 tools/art_hero_swim.py sheet out.png`, `... contact out.png <sektor>`, `... frame out.png t1 t2`.

### 5.1 Zwei Ebenen je Frame (damit das Wasser echt wirkt)
Der Renderer schneidet jede Pose an einer **Wasserebene im Modellraum** (z = Wasserlinie, je Clip gewählt):

| Datei | Inhalt |
|---|---|
| `player_swim.png` | alles **über** der Wasserlinie, scharf, normal beleuchtet |
| `player_swim_under.png` | alles **darunter** als Silhouette mit Schattierung; im Spiel getönt, gebrochen und gedimmt (Shader, 6.2) |
| `player_swim_blood.png` | Blut-Schwellkarte (nur der obere Teil; Verband am Bauch liegt unter Wasser) |
| `data/hero_rig.json` `"swim"` | je Frame: Wasserlinie (y in px relativ zum Anker), Kopfpunkt, Handeintritte (für Spritzer), Mundpunkt (Atemblasen), Fußpunkte (Tritt-Wellen), Fps, Ereignisse |

Rahmen **64 × 56 px**, breiter als die Gehrahmen (48 × 56), damit ausgestreckte Arme beim Kraulen nie am Rand schneiden (gleicher Grund wie bei `player_emerge`). Anker = Körpermitte auf der Wasserlinie, Sprite-Versatz wird einmal festgelegt und gilt für alle Clips. Kein Schatten wird eingebrannt.

### 5.2 Clips (8 Reihen = Richtungen E SE S SW W NW N NE wie überall)

| Clip | Frames | fps | Beschreibung |
|---|---|---|---|
| `tread` | 12 | 8 | Wassertreten: aufrecht, Kopf und Schultern heraus, Arme führen Kreise knapp unter der Oberfläche, Haar schwimmt auf; Körper hebt/senkt sich 1 px, Atem sichtbar |
| `breast` | 14 | 9 (× Tempo) | Brustschwimmen: Oberkörper nach vorn geneigt (`pitch` ≈ 1,0), Kopf oben, Arme ziehen einen Herzbogen, Gleitphase, Froschtritt unter Wasser (nur `under` sichtbar, plus Ferse/Fuß blitzt am Ende des Tritts) |
| `crawl` | 16 | 14 (× Tempo) | Kraulen: flach (`pitch` ≈ 1,35), Gesicht zeigt zur Fahrtrichtung bzw. dreht alle 4 Züge zur Seite zum Atmen, Arme wechseln mit Rückholphase über Wasser, Beine paddeln, Haar streift nach hinten; Armeintritte lösen Spritzer aus |
| `float_dead` | 6 | 4 | Treiben bei 0 HP: auf dem Rücken, Arme locker, Haar fächert (ersetzt das violette Down-Bild im Wasser, optional) |

Richtungsbesonderheiten (Perspektive 3/4 von schräg oben): Von hinten (N) liest Kraul über Arme und Rücken, von vorn (S) über Gesicht und Armbögen; die Pose-Schlüssel bekommen je Sektor eine kleine Kamerakorrektur (`yaw`), damit Arme nicht hinter dem Kopf verschwinden.

### 5.3 Übergänge (jeder ein eigener Clip, ein- und ausgespielt)

| Übergang | Frames | Inhalt | Ereignisse |
|---|---|---|---|
| `enter` (Waten → Schwimmen) | 7 | Wassertiefe überschreitet Hüfte, Füße lösen sich, sie lehnt sich vor, erste Armzüge | `lift` (Füße ab), `splash_small` |
| `exit` (Schwimmen → Waten, Aufstehen) | 7 | Füße finden Grund, Oberkörper richtet sich auf, Wasser läuft ab | `ground`, `drip` |
| `dive` (Kopfsprung, Sprint → Wasser) | 12 | Anlauf-Sprung (Körper horizontal gestreckt, Arme vor), Spitze eintauchen, Beine folgen mit Spritzerkrone, Auftauchen mit Atemzug, Haar zurückwerfen | `leap`, `splash_big`, `surface`, `gasp` |
| `tread→breast`, `breast→tread` | 5 + 5 | Lehnen nach vorn/zurück, Beine wechseln Tritt | – |
| `breast→crawl`, `crawl→breast` | 4 + 4 | Zug-Rhythmus beschleunigt/beruhigt, Kopf senkt sich/hebt sich; **Phasen angeglichen** (Armposition des Brustzugs ≈ Kraul-Eintritt), kein Sprung im Bild | – |
| `shake` (nach dem Aufstehen) | 10 | Wasser aus dem Haar schütteln, kurz abstreifen, Mantelschöße ausdrücken; abbrechbar durch Eingabe | `shake` (Tropfen), `wring` |
| `hit` | 1 Zusatzframe je Technik | Treffer-Flackern wie üblich (`hit_flash`), kein Rückstoß-Sprung, Wasserspritzer | – |

Nahtlose Zyklen: `tread`, `breast`, `crawl` beginnen und enden in derselben Pose; ihre Phase wird beim Wechsel übernommen (`_swim_phase` 0..1), nicht neu gestartet. Beim Anhalten gleitet `breast` noch 0,3 s (Geschwindigkeit baut ab, Frame hält Gleitpose), dann `tread`.

### 5.4 Nassszustand
Kein eigenes Blatt: der Spieler-Shader (`assets/shaders/hit_flash.gdshader`) bekommt `wet` (0..1): Farben dunkler und sättigter, Haar mit Glanzpunkten, Mantel schwerer (leichtes `droop`-Verhalten wird nicht zur Laufzeit gemacht, nur Farbe). Nach dem Verlassen des tiefen Wassers (und halb bei Waten) fällt `wet` über ~25 s auf 0. Dazu Tropfen aus Mantelsaum und Haarspitzen (`CPUParticles2D`, sparsam, am Anfang häufiger), und **nasse Fußspuren** (`Terrain`-`footprint`, Farbe dunkler, 4 s Lebenszeit, nur auf Land/Erde).

### 5.5 Mitgetragenes
- **Waffe/Hand:** `AttackComponent` zeichnet im Schwimmen weder Arm noch Waffe (Sheathed, Hand-Rig `swim` liefert keine Hand). `always_drawn` bleibt aus.
- **Schmuck:** `art_hero_jewelry.py` erhält das Blatt; Punkte unterhalb der Wasserlinie (`water_y` im Rig) werden von `TalismanArt` nicht gezeichnet. Ohrringe und Kette bleiben sichtbar, solange sie über Wasser liegen.
- **Verband/Blut:** unter Wasser nicht sichtbar. Beim Ausstieg aus dem Wasser läuft kurz rosa Wasser aus der Wunde (nur verwundet), Blutdecke wird nicht weggewaschen.

## 6. Texturen und Wasserdarstellung

### 6.1 Bestandteile am Schwimmer (neuer Knoten `SwimWater` ersetzt `WaterOverlay`, solange `swim` > 0)
Sortierung wie beim Overlay: unterhalb der Füße, damit er nach dem Sprite gezeichnet wird; nur der Wasserring hinten liegt davor.

1. **Wasserring hinten** (`z` unter dem Sprite): flacher Ellipsenkranz (3/4-gestaucht, Verhältnis 1 : 0,45) in `FILL` `438780` mit Pixelraster-Rand, lila-türkisem Schatten auf der Oberfläche unter dem Körper.
2. **`under`-Ebene**: Silhouette unter Wasser, Shader `swim_under.gdshader`: Farbe zu `FILL`/`438780` gemischt, 55 % dunkler, Zeilen verschieben sich mit der Wellenfunktion um **ganze Pixel** (wie `sway_rows`), jede 5. Zeile blitzt als Glanz. Tiefer = blasser (dithert aus).
3. **Wasserlinie vorn**: Saum aus hellen Pixeln (`RIM` `91bbae`, Schaum `bfe9ff`) an der Wasserlinie der Rig-Daten, tanzt in 2–3-px-Wellen, bricht beim Zug auf.
4. **Bugwelle** vorn (nur Bewegung): zwei kurze V-Linien, Länge und Helligkeit nach Tempo, Kraul mit kleinem Schaumkamm.
5. **Kielwasser**: Spur aus Wellenringen, die sich ausdehnen und auflösen (vorhandene `WaterRipples`, mit `ripple_cap` 24; ein V-förmiger Auftrag entlang der Spur, je Peer lokal). Im Kraul länger und schaumiger.
6. **Spritzer und Tropfen**: je Armeintritt (Rig-Ereignis) 3–6 Pixeltropfen mit Flugbogen; beim Atmen im Kraul kleine Blasen am Mundpunkt; Beintritt wirft kurze Wellen.
7. **Ringwellen im Wassertreten**: von den Händen langsam sich ausdehnende Doppelringe.
8. **Nacht:** Mondglitzern auf Ringen und Kielwasser über `g_night` (wie die Wasserglitzer), Leuchtquallen und Wasserglühen werfen schwaches Licht auf den Schwimmer (Weltlicht, nichts Unlit); Void-Verderbnis-Küste bleibt Sperre.
9. **Eintauch- und Austauch-Spritzer** (`dive`, `enter`, `exit`): Krone aus Pixeltropfen (kurz, `Unlit` mit Alpha, damit sie nachts nicht verschwinden).

### 6.2 Neue Dateien
- `assets/shaders/swim_under.gdshader`, `swim_surface.gdshader` (Saum/Bugwelle).
- `assets/effects/swim_*.png` kleine Spritzer-/Wellen-Sprites (Pixelkunst, `tools/art_swim_fx.py`): Tropfen (3 Größen), Krone (6 Frames), Bugwelle (4 Frames je Tempo), Schaumkamm (4 Frames), Blasen (3).
- Audio `tools/audio_swim.py` → `assets/audio/swim/`: Eintauchen (klein, groß), Zugrauschen (Brust-Loop, Kraul-Loop, Tempo ändert Pitch), Atmen/Prusten, Ausstieg/Tropfen, Schütteln. Synthetisierte Platzhalter wie überall; positionales Audio für Peers; Loop-Lautstärke folgt `velocity`.

### 6.3 Wasseroberfläche selbst
`river_water.gdshader` hat 8 `disturbances` (Felsen/Quellen). Schwimmer brauchen eigene Slots: Uniform `swimmers[4]` (x, y, Radius, Energie) je Chunk-Material, vom Spieler jeden Frame gefüllt (nur Chunks, die sie schneiden); das Wasser wirft Ringe/Dellen um sie. Kein Eingriff in die gebackenen Masken.

## 7. Eingabe und Anzeige
- Bewegung wie bisher (WASD / Stick), **Sprint-Taste = Kraul**, kein neuer Eingabepfad (`InputManager` bleibt einzig). Blink/Schleichen sind in Wasser gesperrt (Kappen im Hinweis grau).
- `HintCard` `hint: "swim"` beim ersten Eintritt (Taste „SPRINT“ als `VineStyle.key_cap`, Beschriftung „SCHNELL“; zwei Zeilen, blüht und welkt wie die anderen). Flag `swim_hint_seen`.
- Staminaranke zeigt den Verbrauch wie beim Sprint; bei Erschöpfung pulst sie türkis→rot (keine neue UI).
- Cursor: eigener Look nicht nötig (BUSY-Look entfällt, Standard AIM wird ARROW-ähnlich ohne Waffe → neuer Look `SWIM` optional).
- Kamera: leichte Absenkung der Sicht (Kamera 1 px tiefer, Bob mit dem Zug), Spritzer-Shake bei Kopfsprung klein (`Player.add_shake`).

## 8. Welt und andere Systeme

| System | Wirkung |
|---|---|
| `Terrain` / `terrain.json` | `deep_water` bekommt `swim: true`, `speed` entfällt, `allow_sprint` wird `true` (Kraul); `allow_blink` bleibt `false`; Schritt-/Fußspurenarten bleiben für Waten |
| `WorldRivers` | `wade_data` liefert zusätzlich `swim` (bool), `current` (Vector2), `depth_amount`; Signal `depth_attached(body)` |
| Angeln | Wurf abgebrochen, wenn sie ins Wasser geht; Schwimmen erschreckt Fische in 40 px (`scare_fish`), nicht beim Kraul in 80 px |
| Tiere | Enten/Reiher/Frösche flüchten vor einem Kraul wie vor Sprint (`noise_scale`) |
| Pflanzen | `RiverDetails` biegt Pflanzen schon vor Spielern (Radius-Avoid); Schwimmer wird als größerer Radius gemeldet |
| Tageslicht | `DaylightField` gilt weiter, Schwimmer bekommt Sonnenglitzer (wie Wasserglitzer) |
| Speichern | Nichts: Schwimmzustand wird nicht gespeichert, Spieler startet immer an einer Ufer-/Watposition (Spawn im Wasser wird zum nächsten Land versetzt) |
| Gegner | siehe 4.3; Listeners Schuss und Brecher-Rennen kommen nicht über tiefes Wasser; Fernangriffe treffen Schwimmer wie sonst |

## 9. Daten (`data/swim.json`, Skizze)

```json
{
  "enter_amount": 0.92, "exit_amount": 0.80, "min_state_time": 0.25,
  "speeds": {"tread": 0, "breast": 34, "crawl": 58, "tired": 24},
  "stamina": {"tread": 3, "breast": -4, "crawl": -14, "tired_resume": 0.10},
  "noise": {"tread": 0.2, "breast": 0.5, "crawl": 1.0},
  "current": {"max_drift": 0.18, "against": 0.15},
  "transitions": {"enter": 0.35, "exit": 0.3, "dive": 0.7, "shake": 0.9},
  "wet": {"seconds": 25, "drip_rate": 6}
}
```

## 10. Umsetzungsreihenfolge

1. **Logik ohne Kunst:** `data/swim.json`, `SwimComponent` (Kind des Spielers, Zustandsmaschine, `swim`-Property, Stamina, Kollisionsausnahmen über `river_depth`), `WorldRivers`-Signal, Terrain-Einträge, Stand-in: `breast` zeigt das Gehblatt tiefer im Wasser. Test `tools/test_swim.tscn`: Zustandswechsel, Hysterese, Ausnahmen setzen und räumen, Erschöpfung, kein Durchlaufen für Gegner, Netz.
2. **Körperblätter:** `tools/art_hero_swim.py` (zuerst `breast` + `tread` + `enter`/`exit`, dann `crawl`, `dive`, `shake`), Rig-Daten, Blut, Schmuck-Punkte; `Player._use_sheet(13)`/`_animate`-Zweig.
3. **Wasserdarstellung:** `SwimWater` + Shader + Effekt-Sprites + Disturbances.
4. **Übergänge verbinden:** RPC, Phasenübergabe, Kopfsprung, Schütteln, Nassshader, Fußspuren.
5. **Ton:** `tools/audio_swim.py`.
6. **Feinschliff:** Strömung (Stufe 2), Hinweiskarte, Nacht/Void-Prüfung, Bots-/Netztests, Vorschau `tools/preview_swim.tscn -- --capture=/abs`.

Kunst (Blätter, Effekt-Sprites) laut Projektregel über einen `gpt-6.1-terra`-Subagenten; Logik, Integration und Prüfung bleiben beim Hauptagenten. Kontaktbögen und GIFs landen in `docs/img/` (`swim_clips.png`, `swim_transitions.gif`).

## 11. Offene Fragen (für dich)

1. **Zufluchtsort:** Soll tiefes Wasser vor Nahkämpfern schützen (jetzt: ja, Spinnen/Brecher können nicht folgen)? Alternative: Gegner schwimmen langsam hinterher oder lauern am Ufer.
2. **Kein Ertrinken** (nur Erschöpfung) – so gewollt?
3. **Rüstung/Gepäck:** später „Eisen schwimmt nicht“ (Maren, `docs/characters/maren.md`) – soll schwere Rüstung das Schwimmen verbieten oder Stamina verteuern? Jetzt nicht eingebaut.
4. **Kopfsprung** (12 Frames, eigener Aufwand): im ersten Schritt enthalten oder erst später?
5. **Strömung:** gleich in Stufe 1 mitnehmen oder zunächst reines stehendes Wasser?
6. **Seen:** gelten Seen genau wie Flüsse (`bank.B` ruhiges Wasser, keine Strömung)?
