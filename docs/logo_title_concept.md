# Shadowspore – Logo und Titel-Inszenierung (Konzept)

Status: **Konzept, nichts gebaut.** Dieses Dokument hält fest, was wir uns bisher überlegt haben, damit wir
Schritt für Schritt entscheiden können. Offene Punkte stehen unten unter „Entscheidungen".

---

## 1. Wofür brauchen wir es

| Ort | Wann | Form |
|---|---|---|
| **Hauptmenü** | beim Start des Spiels (das Hauptmenü gibt es noch nicht: `main.tscn` startet direkt in die Welt) | groß, Endlosschleife (Idle), kurzer Aufbau beim Öffnen |
| **Titelkarte im Spiel** | nach dem Prolog (Vorschlag: Ende von `find_help`, nach `slept`, im Schwarz vor dem zweiten Morgen) | volle Aufbau-Animation, ca. 7 s, danach Abgang |
| Kleine Marke | Pause-Menü, Ladebildschirm, Abspann | nur das Standbild oder die Spore |
| Fenster-Icon, Boot-Splash | `icon.svg` ist noch das Standardbild | nur die Spore (ein „O") |

Ein Logo, zwei Zustände: **Aufbau** (einmalig, filmisch) und **Idle** (ruhige Schleife, ohne Wiederholungs-Ermüdung).

---

## 2. Die Idee: zwei O, zwei Seiten des Spiels

**SHADOWSPORE** hat genau zwei O: SHAD**O**W und SP**O**RE.

- Das **erste O** (Shadow) ist eine **Leeren-Spore**: schwarze Kugel, kalter violetter Rand, im Kern ein magentafarbener Puls, wie die Augen und Kerne der Schattenwesen. Es ist leicht „glitchy" (Zeilen rutschen, flackert), wie alle Schattenkreaturen.
- Das **zweite O** (Spore) ist eine **Lebens-Spore**: warm-türkis mit goldenem Kern, wie die Leuchtpflanzen und das Licht der Stadt. Aus ihm steigen die Sporen auf.

Das fasst die Kernidee des Spiels in einem Bild: **Licht ist Land**, und die Leere wächst trotzdem. Die beiden O sind
der Wiedererkennungspunkt für Icon, Siegel und Cursor-artige Kleinformen.

Kleinformen: das Spor-O allein (Fenster-Icon, Pause-Menü), beide O als Paar (Siegel).

---

## 3. Look der Buchstaben

Passend zur Welt (Gestaltungsregeln in `design_guide.md`): Pixelart, Licht von links oben, 3–4 Töne je Material,
1-px-Rand in dunkel getönter Farbe (nie hartes Schwarz), kein Weichzeichnen, Dither statt Verlauf.

**Empfehlung: „Gewachsene Lettern"**
- Buchstaben aus dem **violett-geäderten Holz/Wurzelwerk** der Bäume (wie Wegweiser, Hütte, Stämme): dicke, kantige, leicht schiefe Blockbuchstaben mit Maserung.
- **Unten Leben:** Moos, kleine türkise Schirmpilze und Ranken am Fuß der Buchstaben.
- **Oben Leere:** die Oberkanten sind von der Leere angefressen (ausgefranst, violette Adern kriechen hinein, kleine magentafarbene Risse), die Adern **leuchten** und pulsieren.
- Größe: ca. 320×64 px im 640×360-Bild (halbe Breite), Buchstabenhöhe ca. 40 px, Schriftzug leicht gebogen/„hängend" ist möglich, aber der Standard ist gerade für Lesbarkeit.

**Erste Skizze (Option A):** `docs/img/logo_sketch.png`, erzeugt von `tools/art_logo_sketch.py` (`py -3 tools/art_logo_sketch.py`, reines numpy/PIL, nur eine Look-Studie, im Spiel noch nicht verwendet). Links (SHADOW) frisst die Leere die Oberkanten und violette Adern kriechen hinein, rechts (SPORE) wächst Moos mit türkisen Pilzen; die beiden O sind Schatten- und Lebens-Spore.

**Skizze v2 (gestapelt, Richtung nach Feedback):** `docs/img/logo_sketch_v2.png`, erzeugt von `tools/art_logo_sketch_v2.py`. SHADOW steht über SPORE, die beiden O liegen übereinander (SPORE ist dadurch um zwei Buchstaben nach rechts versetzt). Buchstaben dicker und mit nur 2 px Abstand, zusammenhängend und trotzdem einzeln lesbar. An der Berührungsnaht frisst die Leere von SHADOW das Grün von SPORE an (Tropfen über die Naht, violette Erosion und Adern in den oberen Buchstabenkanten); das Grün wehrt sich mit Moos, das nach oben in SHADOW hineinwächst. SPORE ist lebendiger: Moos-Flächen, Gras, Leuchtknospen, hängende Ranken, Pilze, türkise Lebensadern und aufsteigende Sporen.

Alternativen (zur Auswahl):
- **B – Kristall:** Buchstaben aus Leerenkristall wie die Kristallwände (kühler, glatter, weniger „organisch").
- **C – reine Schattenmasse:** Buchstaben nur als schwarze, glitchende Masse mit leuchtenden Adern (am radikalsten, am schwersten lesbar).

---

## 4. Aufbau-Animation (ca. 7 s)

Alles läuft in **Echtzeit** (pausenfest wie `DeathScreen`), nur mit Pixelraster, keine weichen Überblendungen.

| Zeit | Was passiert |
|---|---|
| 0,0 s | Schwarz. Ein einzelnes Pixel (Spore) pulsiert in der Bildmitte, Herzschlag (leise, wie der Wundrand). |
| 0,8 s | Die Spore keimt: ein Riss aus Leerenviolett läuft waagerecht nach links und rechts (wie die Risse am Weltrand). |
| 1,4 s | Die Buchstaben **wachsen** vom Riss aus: Pixel für Pixel setzen sie sich zusammen (derselbe Effekt wie der Stadtbau: `build_pixels`, jedes Pixel fällt von oben an seinen Platz, ein gepunkteter türkiser Entwurf zeigt, was noch fehlt). Reihenfolge: von der Mitte nach außen, leicht versetzt je Buchstabe (≈ 0,12 s). |
| 3,0 s | Die Oberkanten werden von der Leere angefressen, Moos und Pilze keimen am Fuß. |
| 3,6 s | **Die beiden O zünden:** das Schatten-O wird schwarz, der Magenta-Kern öffnet sich (zwei kurze Flackerer); das Spor-O flammt türkis-golden auf. |
| 4,2 s | Ein **Lichtimpuls** (Doppelpuls wie `VoidGlow.beat`) läuft von links nach rechts durch alle Adern. |
| 4,8 s | Kurzer heller Schlag am letzten Buchstaben, eine Staubwelle aus Pixeln, kleiner Kamerazucker. |
| 5,5 s | Einschwingen in die **Idle-Schleife**. |

**Idle-Schleife (ohne Wiederholungsgefühl):**
- Adern atmen langsam (Doppelpuls alle ~3 s), Pulsphase wandert über die Buchstaben.
- Aus dem Spor-O steigen 6–10 Sporen auf, driften im Wind (gleiche Optik wie die Flaum-/Samenpartikel der Flora), begrenzt (Cap), kein Schwarm.
- Das Schatten-O flackert selten (Glitch ca. alle 6–10 s, 0,2 s).
- Alle ~8 s läuft ein schmaler Glanzstreifen über den Schriftzug.
- Pilze am Fuß schwanken im Wind.

**Abgang (Titelkarte im Spiel):** die Leere frisst den Schriftzug von den Rändern her weg (rückwärts zum Aufbau, ca. 1,5 s) und gibt das Schwarz frei; keine harte Blende.

**Kurzfassung** für spätere Neustarts im Menü: ab 3,0 s (ca. 3 s), Taste überspringt.

---

## 5. Ton (synthetisierte Platzhalter, `tools/audio_title.py`)

Herzschlag · tiefer Drone, der anschwillt · kleines Keimen (knisterndes Reißen des Risses) · hölzernes Knarzen je Buchstabe · kurzer Gong/Chime beim Zünden der O (zwei verschiedene Klangfarben: dunkel/hell) · Sub-Schlag am Ende · danach leiser Atem-Teppich. Lautstärke über Master/Effekte wie alle anderen Sounds.

---

## 6. Technik (Vorschlag)

- **Art** (nur Kunst, vom `gpt-6.1-terra`-Agent, siehe CLAUDE.md): `tools/art_logo.py` erzeugt in `assets/ui/logo/`
  - `shadowspore.png`: das Logo, voll beleuchtet,
  - `shadowspore_glow.png`: nur die leuchtenden Pixel (Adern, Kerne, Pilze), wie die Glow-Blätter bei Bäumen und Büschen,
  - `shadowspore_order.png`: Aufbau-Reihenfolge je Pixel (R = Wachstumszeit, G = Buchstabe), damit der Shader keine festen Zeiten braucht,
  - `spore.png`: Einzel-O (Icon) in beiden Varianten, plus die kleinen Spor-Partikel.
- **Shader** (Wiederverwendung): `build_pixels` (Pixel-Aufbau), `VoidGlow` (Doppelpuls, Halo), `Unlit` für Glow-Ebene, Riss/Leerenkante aus dem `void_edge`-Look.
- **Node:** `TitleLogo` (`src/ui/title_logo.gd`), API `play_build()`, `skip()`, Signal `built`, `idle`, `finished`; Zustände BUILD / IDLE / FADE; eigene Echtzeituhr, Pause/Zeitlupe-fest. Zeiten in `data/title.json`.
- **Einbindung:** Titelkarte als Szene in der Story (`WorldLevel.show_title()`; nach `slept`, einmalig, Flag `title_shown` im Spielstand), später das Hauptmenü (`MainMenu`, VineStyle) als eigene Einstiegsszene.
- **Reduzierte Bewegung:** Option, die Schleife ruhig zu halten (keine Glitches, keine Sporen).
- **Test:** `tools/test_title_logo.tscn` (Reihenfolge, Zeiten, Überspringen, Aufräumen, Pausenfestigkeit) und `tools/preview_title_logo.tscn -- --capture=/abs/ordner` für Bildfolgen.

---

## 7. Vorgehen

1. Dieses Konzept bestätigen (Entscheidungen unten).
2. **Skizzen:** drei Entwürfe der Wortmarke (A/B/C) als Standbild, Auswahl.
3. **Finale Kunst** (Logo, Glow-Blatt, Reihenfolge-Karte, Spor-O, Partikel).
4. `TitleLogo` mit Aufbau und Idle, Sound, Vorschau- und Testszene.
5. Titelkarte in die Story hängen. Danach: Hauptmenü.

---

## 8. Entscheidungen

| Frage | Empfehlung |
|---|---|
| Buchstabenstil | **A „Gewachsene Lettern"** (Alternativen B Kristall, C Schattenmasse) |
| Zwei-O-Motiv (Schatten-O dunkel, Spor-O leuchtend) | ja |
| Wo erscheint die Titelkarte im Spiel? | Ende von `find_help` (nach `slept`, im Schwarz vor dem zweiten Morgen) |
| Tagline unter dem Logo | zunächst keine |
| Hauptmenü | erst nach dem Logo, als eigener Schritt |

---

## 9. Stand: finales Logo mit Standanimationen (gebaut)

Das Konzept oben ist für die Form überholt, so ist es gebaut (die **Aufbau-Animation fehlt noch**, Hauptmenü und Titelkarte in der Story auch):

- **Look:** SHADOW über SPORE, die beiden O übereinander, alle Buchstaben einzeln (dünne Trennlinie, 3 px Abstand), 5 px Tiefe nach oben rechts. SHADOW = Schattenkreatur (schwarzes Fleisch, violette Kante, Adern, Kerne), SPORE = das Holz der Bäume und Wegweiser (mauve) mit Moos, Schirmpilzen, kleinen Pflanzen und einer großen Sporenblume rechts mit Wurzel. Im SHADOW-O ein beobachtendes magentafarbenes Auge, im SPORE-O die Stadtlaterne auf einem kleinen Steinhaufen am unteren Innenrand, ihr Licht fällt auf den Ring. Die O sind rund (52 x 54 px, Ring 14 px an den Seiten, 12 oben und unten).
- **Generator:** `py -3 tools/art_title_logo.py` (deterministisch, Seed 31) schreibt die Ebenen nach `assets/ui/logo/` (`title_base`, `title_plants` + `title_plants_sway` (R Gewicht, G Phase), `title_glow` + `title_glow_map` (R Phase, G Art x 32), drei Halos `title_halo_void/life/lamp`, zwei Orb-Blätter `title_orb_void/life` mit je 8 Bildern à 40 px), die Geometrie nach `data/title_logo_layout.json` und Vorschauen nach `docs/img/title_logo_preview*.png`. Danach `Godot --headless --import`.
- **Node:** `TitleLogo` (`src/ui/title_logo.gd`, `Control`, 440 x 240, ganzzahlig platzieren). Eigene Echtzeituhr (`clock()`, läuft bei Pause und Zeitlupe weiter, `set_time(t)` friert sie für Tests und Captures ein, `release_time()`), alles ist eine reine Funktion dieser Uhr. Abstimmung in `data/title.json`.
- **Idle-Leben:** Pflanzen wiegen sich in ganzen Pixeln (`title_plants.gdshader`, Wurzelpixel bleiben); Adern und Kerne schlagen wie ein Herz, Wurzeln atmen, die Sporenblume schwillt (`title_glow.gdshader`); das Auge wechselt langsam die Bilder und glitcht ab und zu; die Laterne flackert (7 Bilder/s, unregelmäßig); ein Glanzband zieht alle ~12 s schräg über die Kanten und einige Zeilen von SHADOW rutschen kurz seitlich (`title_base.gdshader`); die Halos atmen (`title_halo.gdshader`, additiv); zustandslose Partikel: Sporen steigen von der Blume und den Pflanzen auf, violette Leeren-Mote steigen von SHADOW, Tropfen fallen an den Nahtstellen.
- **Prüfen:** `tools/test_title_logo.tscn` (headless, Ebenen, Layout, Uhr-Funktionen, Pause-/Zeitlupenfestigkeit), Capture `Godot --rendering-driver opengl3 --path . tools/preview_title_logo.tscn -- --capture=/abs.png [--t=3.5]` oder Bildfolge `-- --strip=/abs/ordner --n=12 --dt=0.25`. Abweichung des Engine-Captures bei t=0 vom Generator-Standbild: nur Partikel, Puls und Pflanzenschwung.
- **Aufbau-Animation (gebaut, ca. 6,2 s, Zeiten in `data/title.json` `build`):** `TitleLogo.play_build()` / `skip_build()` / `is_building()`, Signale `impact` (der Schlag, hier kann der Besitzer die Kamera rütteln) und `built`; alles ist eine reine Funktion der Aufbauzeit (`build_params(bt)`, getestet).
  - 0,0 s ein Spor-Pixel pulsiert im Herzschlag in der Mitte; 0,8 s der Riss am Boden (die leuchtende Kante, `kind 5`) bricht von der Mitte nach außen auf; ab 1,5 s zeigt ein gepunkteter türkiser Entwurf, was noch fehlt.
  - 1,8 s bis 4,4 s landen die Buchstaben Pixel für Pixel (`title_order.png`: R Ankunftszeit, G 255 = gleitet seitlich ein): SPORE fällt von oben und stapelt sich vom Fuß jedes Buchstabens nach oben, von der Mitte nach außen; SHADOW gleitet danach Zeile für Zeile seitlich ein (wie die Glitchzeilen der Schattenwesen). Gelandete Pixel blitzen kurz auf (`title_base.gdshader`).
  - 3,6 bis 4,7 s wachsen die Pflanzen (Wurzel zuerst, Spitzen zuletzt, das Gewicht aus der Sway-Karte); 4,5 s der Schlag (Aufblitzen, Staubwelle aus Pixeln, Signal `impact`); 4,7 s zündet das Auge (zweimal Flackern), 4,95 s die Laterne (Halo überschießt kurz); 4,8 bis 5,8 s läuft die Lichtfront von links nach rechts durch Adern, Kerne und Wurzeln; ab 5,6 s blenden die Idle-Partikel, Glanz und Glitch ein.
  - Vorschau: `Godot --path . tools/preview_title_logo.tscn -- --build` (Taste B startet neu); Bildfolge `-- --build --strip=/abs/ordner --n=16 --dt=0.4`.
- **Offen:** Ton (`tools/audio_title.py`), Hauptmenü (Konzept: [hauptmenue_konzept.md](hauptmenue_konzept.md)) und Titelkarte nach `slept`, Abgang rückwärts, Option für reduzierte Bewegung.
