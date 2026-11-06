# Gegner-Dossier: Leerenhorcher (Void Listener)

> *„Du glaubst, du bist allein im Unterholz, weil kein Ast knackt. Doch er pirscht nicht mit den Augen. Er horcht auf das Schlagen deines Herzens, auf das Reiben deines Ledermantels, auf das Ziehen deiner Klinge. Und wenn sich sein gespaltener Rachen lautlos dehnt, ist die Resonanzwelle bereits in der Luft.“*

---

### 1. Basis & Physische Präsenz
* **Name:** Leerenhorcher (intern: `void_listener`)
* **Klassifizierung & Rang:** Resonanz-Schattengestalt / Akustischer Fernkampf-Jäger
* **Habitat & Vorkommen:**
  * Schattige Waldlichtungen, dichte Farnwälder im Nebelwald, verfallene Hallen, feuchte Stolleneingänge der Mine.
  * Meidet grell erleuchtete Freiflächen am helllichten Tag; nutzt akustisch reflektierende Umgebungen (Bäume, Felswände, Mauern), in denen sich Schallwellen fangen.
* **Rolle im Kampfsystem:**
  * Der **lauernde Scharfschütze und Zonen-Disrupter**.
  * Belauert Spieler aus sicherer Distanz (Idealdistanz 95–133 px), bestraft lautes Vorpreschen (Sprinten, Waffenschwünge) mit tödlichen Schallwellen-Geschossen und stößt unbedachte Nahkämpfer mit einem brutalen frontalen Druckschrei (*Abwehrschockwelle*) zurück.
* **Erscheinungsbild, Silhouette & Anatomie:**
  * **Körperbau & Maße:** Vornübergebeugte, unheimlich lauernde Gestalt mit buckliger Silhouette. Standhöhe ca. 38–44 px (auf Augenhöhe mit Ellie, wirkt aber durch die gebeugte Haltung gedrungener).
  * **Prozedurales Rigging (`ListenerRig`):** Keine vorgebackenen Sprite-Sheets! Die gesamte Kreatur wird Bild für Bild als lebende prozedurale Pixelgeometrie berechnet und gezeichnet:
    * **Zwei hintere Standbeine:** Kürzere, dickere Gliedmaßen (Stärke 4.5), die den Rumpf fest am Boden verankern.
    * **Zwei vordere Tastfühler (`tactile: true`):** Deutlich längere, geschwungene Fortsätze (Stärke 3.2), die wie lebendige Sensoren sanft über den Boden gleiten und Vibrationen erfassen.
    * **Thorax & Rippenbögen:** Ein vielschichtiger, atmender Rumpf mit drei sichtbaren Rippennähten auf jeder Seite, durch die violettes Leerenblut pulsiert.
    * **Das dreilappige Haupt:** Kein Kiefer oder Maul im irdischen Sinn. Drei fleischige Loben spalten sich um einen tiefen zentralen Spalt auf (`_head`, `_opening`). Beim Laden von Energie dehnen sich die Platten wie Blütenblätter; beim Schrei reißen sie bis zu 165 % ihrer Normalbreite auf.
  * **Farben & Material-Palette:**
    * Basisschwarz & Fleisch: `07040d` (Dunkelgrund) über `0e0919` (Fleischgewebe) bis `1a1030` (obere Chitinplatten).
    * Umrisslinie: Scharfes `040208` (1 px).
    * Kantenlicht & Adern: Kaltvioletter Rim `5a36b8`, lebendige Adern `8a4dff`.
    * Leuchtkerne (Unshaded): Magentafarbene Augenpunkte `ff4fd8` an den Seitenlappen, Druckkern im Rachenspalt in Weiß-Violett (`ecd2ff` / `fff7ff`).
* **Erster Eindruck auf Ellie / Fremde:**
  * Beklemmende Fremdartigkeit. Das Wesen wirkt blind, aber erschreckend wach. Sein ganzer Körper zittert in subtilen Mikroschwingungen, als würde er jede Luftbewegung wie ein Seismograph aufzeichnen.
  * Sensorik: Trockene, knisternde Stille um die Kreatur herum – als würde sie Geräusche aus ihrer unmittelbaren Umgebung aufsaugen.

---

### 2. Psychologischer Kern (Die innere Mechanik & Jagdtrieb)
* **Grundantrieb (Want / Sensorischer Trieb):**
  * **Die Auslöschung aller Frequenzen.** Jedes akustische Signal der lebendigen Welt – Herzschlag, Schritte, Atemzüge, klirrender Stahl – reizt sein Resonanzorgan wie brennende Nadeln. Es greift an, um die Quelle des Schalls zu vernichten und Stille zu erzwingen.
* **Tiefstes Bedürfnis (Need):**
  * **Das absolute Vakuum (Null-Echo).** Der Horcher sehnt sich nach der lautlosen, unbewegten Kälte der reinen Leere, aus der er einst gerissen wurde.
* **Die Sollbruchstelle (Schwachpunkt & Urangst):**
  * **Leisetreter & Schleicher:** Wer schleicht (`sneak`), reduziert den Hörradius des Horchers dramatisch von 180/255 px auf winzige 48 px! Ellie kann sich ihm von hinten fast unbemerkt nähern.
  * **Die offene Heckflanke:** Seine berüchtigte Abwehrschockwelle deckt nur einen 115°-Fächer nach vorn ab. Sein Rücken und seine Seiten bleiben völlig schutzlos. Nach dem Schrei verharrt er für lange **1.05 Sekunden** in schwerer Erschöpfung (`RECOVER`).
  * **Zerbrechliche Physis:** Mit nur 38 HP hält er deutlich weniger aus als die Schattenspinne (48 HP). Schwere Treffer (Knockback $\ge 70$) unterbrechen seine Ladephasen sofort.
* **Der innere Widerspruch:**
  * **Allwissendes Gehör vs. panische Nahkampf-Verletzlichkeit:** Er hört eine Stecknadel auf 200 Pixel fallen, gerät jedoch in Panik, sobald ein Schwertträger seine Nahdistanz (unter 43 px) durchbricht, und verfeuert überstürzt seinen Schutzzauber.
* **Jagdmuster & Taktik:**
  * Geht nie in den Nahkampf. Weicht rückwärts zurück (`retreat_speed` 42 px/s), wenn der Spieler näher als 95 px kommt, und umkreist ihn seitlich tänzelnd (`strafe_speed` 29 px/s) in der Schusszone.

---

### 3. Akustik & Signal-DNA (Die Stimme des Schreckens)
* **Klangbild & Sound-Design (`tools/audio_listener.py`):**
  * Keine billigen Tieraufnahmen oder Monstergebrüll. Ausschließlich synthetisierte, spektrale Phasenlaute (Lautstärke $-8$ dB, mit subtiler Tonhöhen-Streuung):
  * **1. Laden (`listener_charge.wav`, 0.8 s):** Ein tiefes, saugendes Einatmen von Raum und Luft (steigender Sinuston von 53 Hz aufwärts, gefiltertes Rauschen wie knisterndes Gewebe).
  * **2. Schuss (`listener_wave.wav`, 0.55 s):** Ein brechender, scharf zischender Resonanzimpuls (145 Hz fallend, spratzelnde Void-Partikel).
  * **3. Schrei (`listener_scream.wav`, 0.6 s):** Eine markerschütternde akustische Druckentladung (82 Hz Impulswelle mit schrillen, metallischen Oberton-Vibrationen).
  * **4. Tod (`listener_death.wav`, 0.8 s):** Ein hohl verwehendes, saugendes Zusammenfallen, als würde ein Tonband abreißen.
* **Körpersprache & Mikrobewegungen:**
  * **Lauschen (`LISTEN`):** Körper wiegt sanft in Resonanz (`_time * 0.9`), die langen Tastfühler tasten in kleinen Kurven über den Moosboden.
  * **Aufmerken (`NOTICE`, 0.42 s):** Rumpf duckt sich blitzartig, der Kopf hebt sich ruckartig zur Schallquelle, der Spalt weitet sich um 25 %.
  * **Aufladen (`CHARGE` / `BRACE`):** Der Rumpf komprimiert sich wie eine Feder, die Vorderglieder spreizen sich weit nach außen, violette Adern fluten die Brust.
  * **Der Schrei (`SCREAM`):** Die drei Kopflappen reißen maximal auf, der Oberkörper bäumt sich mit 8 px Vorwärtsneigung auf, während die Tastglieder krampfhaft nach hinten schlagen.
* **Telegraphing & Warnflächen:**
  * **Spaltprojektil:** Ein schmaler, roter Zielstreifen (Radius 6 px + 4 px Polster) wächst vom Horcher zum Zielpunkt (Reichweite bis 152 px). Exakt **0.25 s vor Schussabgabe** friert die Ausrichtung ein (`aim_locked`).
  * **Schockwelle:** Roter 115°-Bodenfächer mit 46 px Radius.
  * **Bildschirm-Refraktion:** Während des Schreis bricht der Post-Processing-Shader (`listener_shock.gdshader`) das Screen-Raster für 0.3 s in einer sichtbaren Schockwelle.
* **Was der Horcher NIE tun würde:**
  * Dumpf brüllen oder fauchen wie ein Wolf oder Bär.
  * Blindlings auf die Spielfigur zustürmen.
  * An Klippen emporklettern (ihm fehlen die Greifkrallen der Spinne; er muss Treppen und Rampen nutzen).

---

### 4. Kampfmechanik & Verhaltensdynamiken (Die KI-DNA)
* **Sensorik & Hörmatrix (Host-autoritativ):**
  * Das Gehör reagiert auf jede Fortbewegungsart des Spielers:

| Spieler-Aktion | Hörreichweite | Anmerkung |
|---|---|---|
| **Schleichen** (`sneak`) | **48 px** | Nahezu taub gegenüber Schleichenden! |
| **Gehen** (`walk`) | **180 px** | Standard-Wahrnehmung bei normaler Bewegung. |
| **Sprinten** (`sprint`) | **255 px** | Hört Joggen und Sprinten fast über den ganzen Bildschirm! |
| **Waffenschwung** (`swing`) | **240 px** | Ein Schwertstreich alarmiert ihn selbst im toten Winkel. |
| **Sichtkegel** (`sight`) | **175 px** | Vorwärtsgerichteter Sichtwinkel (Kegel ca. 70°). |
| **Deckung / Wände** | **Faktor 0.7** | Wände und Klippen dämpfen den Schall (`sound_occlusion`). |

  * **Akustisches Gedächtnis (`memory_seconds: 8.0`):** Er merkt sich die Position des letzten wahrgenommenen Geräuschs für volle 8 Sekunden und untersucht den Ort bei Sichtverlust aktiv (`SEARCH`, 2.8 s lang).
* **Distanz- & Fluchtlogik (`_hunt`):**
  * Bevorzugter Kampfabstand: **95 bis 133 px**.
  * Distanz $< 95$ px: Weicht im Rückwärtsgang mit 42 px/s zurück.
  * Distanz 95–133 px: Strafe-Kreisen mit 29 px/s für freie Schusswinkel.
  * Distanz $> 133$ px: Rückt kontrolliert mit 48 px/s nach.
* **Vollständiges Moveset:**

| Aktion | Trigger & Distanz | Windup (Aim-Lock) | Ausführung & Flug | Recovery | Schaden / Effekt |
|---|---|---|---|---|---|
| **Spaltprojektil** (*Resonance Wave*) | 45–152 px Distanz, freier Schusswinkel | 0.80 s (Lock bei 0.55 s) | 210 px/s Projektiltempo, Reichweite 152 px | 0.85 s | **14 Schaden**, 65 Knockback. Projektil `ResonanceWave` fliegt unabhängig vom Schützen weiter; bricht an Wänden & Klippen; trifft jeden Spieler max. 1×. Cooldown: 1.6 s. |
| **Abwehrschockwelle** (*Defensive Scream*) | Triggert bei $\le 43$ px Nahbereich | 0.60 s (Lock bei 0.35 s) | 0.22 s (Schadensimpuls bei 0.13 s) | 1.05 s | **9 Schaden**, massiver **115 Knockback** (schleudert Ellie weit zurück!). 115° Fächer, 46 px Reichweite. Screen-Shake & 5 Schattenrisse. Heckflanke offen! Cooldown: 2.8 s. |

* **Reaktion auf Treffer & Tod:**
  * **Fragile Konstitution:** 38 HP, Stun bei Schaden 0.26 s. Schwere Hiebe (>= 70 Knockback) werfen ihn um (`State.HURT`) und brechen das Aufladen ab.
  * **Tod:** Bei 0 HP sackt die Thorax-Masse zusammen, die Loben fallen schlaff zur Erde. Er hinterlässt wie die Spinne einen 8-Tentakel-Schattenbefall (`ShadowTrailComponent.infest`), der die Erde kontaminiert.

---

### 5. Lore, Ursprung & Welt-Verflechtung
* **Die Wurzel im Void:**
  * Während die Schattenspinne das fleischliche, greifende Raubtier der Leere ist, verkörpert der Leerenhorcher die akustische Verzerrung. Er entsteht dort, wo die Stimmen der Vergangenheit und der Hall zerfallener Festungen von der Leere verschluckt wurden.
* **Beute & Verwertung:**
  * **Erfahrung:** 12 XP.
  * **Währung:** 4–9 Kupferstücke.
  * **Materialien:**
    * 65 % Chance: 1–2× **Leersplitter** (`void_splinter`).
    * 8 % Chance: 1× **Schattenkern** (`shadow_core`).
* **Beziehung zu den Hauptfiguren:**
  * **Zu Ellie:**
    * Ellie lehrt der Horcher das lautlose Überleben. Ellie, die sonst gern keck murmelt oder unbedarft durchs Laub rennt, wird in seinem Revier gezwungen, den Atem anzuhalten und im Schleichgang zu pirschen.
  * **Zu Valdric:**
    * Valdrics Albtraum in puncto Sensorik. Die schwere Eisenrüstung klirrt bei jedem Schritt und macht Valdric für den Horcher über den halben Wald hinweg ortbar. Zudem lässt die Abwehrschockwelle Valdrics geschlossenen Helm wie eine Glocke dröhnen, was den Ritter desorientiert.

---

### 6. Voice-Check (In-Game Encounter Momente)

> **Lauernde Stille (Ellie lernt das Schleichen):**
> *„(flüstert kaum hörbar) Valdric... bleib stehen. Keinen Schritt weiter. Nimm die Fersen hoch... Siehst du die dünnen Fühler da vorne zwischen den Farne wedeln? Das Ding hat keine Augen im Gesicht, aber wenn du jetzt mit deinen Eisenstiefeln auch nur einen Zweig brichst, dreht es sich um.“*

> **Der Angriff (Resonanz-Einschlag):**
> *(Ein tiefes, ziehendes Knurren wie von berstendem Eis. Die Luft über dem Farnfeld flimmert. Ein weiß glühender Kern schießt pfeifend aus dem Kopfspalt der Kreatur hervor, zieht einen violetten Schleier hinter sich her und zerschellt mit ohrenbetäubendem Krachen an einem Felsen – Splitter regnen auf das Moos.)*

> **Valdrics Taktik (Die Schwachstelle ausnutzen):**
> *„Es lädt wieder auf! Tritt nicht frontal heran, Ellie – umkreise es! Lauf in seinen Rücken, während es den Schrei nach vorn entlädt! Der Stoß bricht nach hinten nicht durch!“*

> **Der Konter (Bruch der Schockwelle):**
> *(Ellie huscht im Schleichgang hinter den erschöpften Horcher. Während die Kreatur noch keuchend die drei Kopflappen schließt, rammt Ellie die Klinge mit voller Wucht in die ungeschützte Rückenader. Mit einem hohlen, nachhallenden Seufzen sackt das Wesen in sich zusammen.)*

---

### 7. Enemy Artist & Rigging Notes (Für Shader- & Rig-Entwickler)
1. **Keine rotierenden Sprites:**
   * Der Leerenhorcher besitzt kein vorgezeichnetes Dreh-Spritesheet. Seine Gliedmaßen, der Thorax und die drei Kopflappen werden komplett prozedural aus Bezier-Kurven und Pixel-Primitiven in `ListenerRig.gd` generiert.
2. **Die Lobe-Mechanik:**
   * Die drei Kopfteile (`crown` und zwei seitliche `plate`-Elemente) müssen sich synchron zur Ladevariable `_opening` physisch spreizen. Bei `_opening > 0.15` wird der innere Leuchtspalt sichtbar und zeichnet eine unshaded weiße Kernlinie (`CORE: ecd2ff`).
3. **Farb- & Beleuchtungsregeln:**
   * Basiskörper bleibt dunkel und weltbeleuchtet (`DARK` / `FLESH` / `UPPER`).
   * Nur Adern (`VEIN`), Augen (`EYE`) und Kerne (`CORE`) liegen auf separaten Additiv-Glow-Knoten (`_back_glow`, `_body_glow`, `_front_glow`).
4. **Resonanzwellen-Lebenszyklus:**
   * `ResonanceWave` darf niemals als Child-Node unter den Horcher gehängt werden! Das Projektil ist ein eigenständiger Welteffekt unter `EnemyProjectiles` und lebt auch dann weiter, wenn der Horcher im selben Moment stirbt.
