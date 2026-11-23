# Shadowspore 2.0 — Konzept: Player Movement & Lebendige Animationen

> **Leitvision für Movement 2.0:**
> In einem Action-RPG ist die Bewegung kein bloßes Transportmittel von Quest A nach Quest B — sie ist **90 % der gesamten Spielzeit**. Im Einklang mit der umfassenden Spiel- und Map-Überarbeitung verschmilzt Ellies Steuerung zu einem **butterweichen, reaktionsschnellen und organischen Instrument**: geerdet und anmutig im Alltag, messerscharf im Kampf und in feinen Details durchzogen von ihrer wahren Natur (*„Ellie ist die Shadowspore“*).

---

## 1. Die 12 Technischen Kernsysteme (`T1–T12`)

1. **T1 — Nichtlineare Bewegungs-Kurven & Taktiler „Sprint-Antritt“ (`LocomotionCurve` in `data/movement.json`):**
   Sofortiger Erst-Impuls (`0 → 45 %` Zieltempo in `45 ms`) gefolgt von organischer Ease-Out-Beschleunigung, kurzer `0,18 s`-Sprint-Antritt (`1,22×` Surge) beim Drücken von `Shift` sowie geschwindigkeitsabhängiges Ausfedern (`Plant-Glide` aus vollem Sprint vs. millimetergenauer Direktstopp aus dem Gehen).
2. **T2 — Intelligentes Corner-Smoothing & Hindernis-Abgleiten (`CornerNudge`):**
   Zwei kurze seitliche Physik-Fühler (`±4,8 px`, `8,5 px` voraus auf Layer `1`) leiten Ellie sanft um Baumstämme, Felsen, Türrahmen, Zäune und 4-px-Klippenkanten herum, ohne Lauftakt oder Sprint-Schwung abzubrechen.
3. **T3 — Kurven-Carving vs. Knackiger „Sprint-Pivot“ (`TurnPhysics` & Analog-Feingefühl):**
   Weite Kurven (`< 68°`) drehen den Geschwindigkeitsvektor direkt ohne Tempoverlust; scharfe 180°-Wenden (`> 125°` im Sprint) lösen ein griffiges `0,13 s`-Einstemmen mit `2,35×` Gegenbeschleunigung aus. Stufenlose Analogstick-Modulation + `75 ms` Diagonal-Grace auf `WASD`.
4. **T4 — Echte Topografie-Physik auf Hängen, Treppen & Nässe (`Slope & Surface Kinematics`):**
   `Relief.level_at`-Gradient steuert Bergauf-Kraftaufwand (`0,88×`) vs. Bergab-Schwung (`1,08×`), Stufen-Mikrotaktung auf `STAIRS`/`STEPS` sowie Straßen-Traktionsbonus (`+6 %`) vs. sanfteren Brems-Glide auf Nässe/Matsch.
5. **T5 — Der „Reisetritt“ (`Wanderfluss` — Kampffreies Ausdauer-System):**
   Außerhalb von Kampf und naher Nachtgefahr wechselt Sprint nach `1,1 s` in den Reisetritt: auf gebauten Wegen/Straßen (`path`, `stone`, `quartz`) **0 Ausdauerverbrauch + `+8 %` Tempo**, in freier Wildnis **`-65 %` Verbrauch** ohne `_winded`-Sperre; bei Gefahr greifen sofort 100 % taktische Kampf-Ausdauerregeln.
6. **T6 — Dynamisches Übersteigen (`Vault`) & Kanten-Absprung (`Ledge Hop`):**
   Host-validiertes Übersteigen flacher Hindernisse (`FallenLog`, fertige Zäune `fence`, Gruppe `vaultable`) im Sprint per `E` (`0,36 s`, voller Schwung bleibt erhalten) sowie gezielter Absprung an sicheren 1-Stufen-`Relief`-Kanten (`0,42 s`, `"HINUNTERSPRINGEN"`).
7. **T7 — Universeller `130 ms`-Input-Buffer & Weiche Follow-Through-Cancels (`FluidActionBuffer`):**
   Ringpuffer für `shadow_step`, `action_primary`, `action_secondary`, `interact` und `sprint`; weiches Überblenden der letzten `0,17 s` (Follow-Through) von Hieben, Pflücken, Wurzelziehen und Kletter-Ausstieg in den Lauf.
8. **T8 — Kinetischer `Schattenschritt` & `Lichtschritt` 2.0 (`SporeStep Kinematics`):**
   Querung flacher Bäche/Bodenrinnen auf gleicher `Relief`-Ebene bei freier Sichtlinie, Wand-Tangenten-Gleiter bei flachen Auftreffwinkeln (`< 36°`) und elastischer `1,14×`-Ausgangsschwung bei gehaltener Richtung.
9. **T9 — Echte Kampf-Fußarbeit & Strafing-Quadranten (`Combat Footwork`):**
   Vier Quadranten relativ zur Zielrichtung (`Vorwärts`, `Strafe Rechts`, `Strafe Links`, `Rückzug`) mit eigener Überkreuz-Beinarbeit (`0,94×` Tempo) und kontrolliertem Backpedal (`0,86×`).
10. **T10 — Adaptive, Pixel-stabile Kamera (`LivingCamera 2.0`):**
    Ruhige `9 px`-Komfort-Deadzone bei Kleinarbeit, weich wachsender Vorlauf bis `38 px` im Reisetritt sowie `65/35`-Zielgewichtung beim Aufladen, Zaubern und im Kampf — synchronisiert mit `SunShadows` & `WaterReflections`.
11. **T11 — Butterweiche 20-Hz-Koop-Interpolation (`Hermite Visual Smoothing`):**
    Getrennter visueller Korrektur-Offset (`exp(-18 * delta)`) plus gepackter Bewegungs-Zustand (`sync_flags`) für ruckelfreie 60–144-Hz-Mitspieler-Darstellung bei 20-Hz-Netzwerk-Ticks.
12. **T12 — Zentraler Welt-Impuls- & Akustik-Bus (`LocomotionImpulse`):**
    Einheitliche Impulse für `LivingGrass`-Bugwellen/Landeringe, Oberflächen-Hörweiten (`StealthComponent.alarm_scale`) und Schatten-Tarnung.

---

## 2. Die 12 Visuellen & Animatorischen Säulen (`V1–V12`)

1. **V1 — Geschmeidigere Lauf-Dynamik & 60-Hz-Arm-Interpolation (`Gait & Subframe Rig`):**
   Weiche Gewichts-Federung (`Down`-Sink nach Fußkontakt) sowie kontinuierliche Subframe-Interpolation (`frac(_walk_time)`) für rechten Arm, Schwert, Stab und Werkzeuge.
2. **V2 — Eigene Übergangs-Posen (`Start`, `Brake`, `180°-Sprint-Pivot` in `player_agile.png`):**
   8 echte Richtungen (`E..NE`) ohne Spiegeln oder Drehen: Vorneige beim Antritt (`3f`), federndes Abstoppen (`4f`) und dynamisches Stiefel-Stemmen mit Haarschwung bei der 180°-Kehrtwende (`4f`).
3. **V3 — Phasenverzögerte Sekundär-Dynamik & Weltwind-Spitzen im Stand:**
   Nachschwingende Silberhaar-Strähnen und Mantelschöße in den Übergängen sowie dezenter, ganzzahlig pixel-gesnappter `WorldWind`-Impuls am unteren Mantel-/Haarsaum im ruhigen Stand.
4. **V4 — Organisches Kurven-Einlenken (`Gaze & Sector Lead`):**
   Sanfte Sektor-Hysterese und Blick-/Oberkörper-Führung entlang geschwungener Laufbögen.
5. **V5 — Lebendiger Waffenarm: Entspannte Reisehaltung vs. Wache Kampfhaltung:**
   Freies Mitschwingen im friedlichen Dorf-/Reiselauf, automatisches Ziehen in Bereitschaft bei Gefahr/Kampf.
6. **V6 — Subtile „Ellie = Shadowspore“-Signatur (`Spore & Sun-Quartz Micro-VFX`):**
   2–3 feine dunkelviolett-lavendelfarbene Sporen-Splitter beim scharfen Sprint-Pivot/Absprung, kurzer unlit Gold-Glint (`#fff0b0`) am Sonnenquarz-Halsband nach Rekondensation und sanfte Nacht-Resonanz naher `Leerenblüten`/Glühpilze.
7. **V7 — Biom-echte Schritt-Poesie 2.0:**
   Morgentau-Tröpfchen & Blütenblätter auf Wiesen, feuchte Sohlenabdrücke nach Wasser/Regen, absinkende grüne Sporen im Hexenwald und helle Quarzfunken in der Singenden Öde.
8. **V8 — Handgeformte `Vault`- (`8f`) & `Ledge-Hop`-Animationen (`10f`):**
   Einhändiger Stützsprung über gefallene Stämme/Zäune und luftiger Kanten-Absprung mit echter Bodenschatten-Trennung, inklusive aller Frisur- und Outfit-Layer.
9. **V9 — Atmosphärisches Schleichen 2.0 (`Prowl`):**
   Weiche 2-Frame-Duck-Brücke und dezente `12 %` Nacht-Indigo-Konturtönung (`prowl_shade`) unter dichtem Blätterdach und Nachtschatten.
10. **V10 — Umwelt-fühlende Körpersprache (`Environmental Micro-Acting`):**
    Leichte Schutzhaltung gegen Sturmregen und kontextbewusste Ruhe-Impulse an Klippen und Feuern.
11. **V11 — Kinetische Begleiter-Harmonie mit `Krümel` (`Companion Flow`):**
    Gegenphasiges Schulter-Wippen beim ruhigen Gehen, sofortiges Abheben bei Sprint/`Vault`/`Schattenschritt` und elegantes Mitsegeln auf Ellies Flanke im Reisetritt.
12. **V12 — Nahtlose Harmonie mit `LivingGrass`, `SunShadows` & `WaterReflections`:**
    Echte Stiefel-Einbettung in den 6-px-Grasbändern, höhenkorrekter Sonnenschatten-Versatz (`air_height`) im Sprung und vollständige Wasserspiegelung aller neuen Posen.
