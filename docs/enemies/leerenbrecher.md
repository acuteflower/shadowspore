# Gegner-Dossier: Leerenbrecher (Void Crusher)

> *„Der Boden bebt nicht aus Zorn, sondern unter totem Gewicht. Ein Schlagarm aus zackigem Leerenbasalt, ein Körper aus hungrigen Schattenfasern. Schlag nicht auf seine Brust, Ellie – du schlägst auf eine Festungswand. Zwing ihn zum Fehlschlag, weiche durch den Staub, und dann ramme die Klinge in seinen Nacken!“*  
> — Valdric, beim ersten Sichten an den Felsen der Glasklippen

---

### 1. Basis & Physische Präsenz
* **Name:** Leerenbrecher (intern: `void_crusher` oder `void_breaker`; Story-Titel: *Der Hüter der Tiefe*)
* **Klassifizierung & Rang:** Höhere physische Leeren-Manifestation / Schattengestalt (Brute- / Juggernaut-Typus)
* **Habitat & Vorkommen:**
  * Tiefe Minenstollen (*Mine*), Geröllabhänge der Glasklippen (*Glasklippen*), versunkene Ruinenmauern (*Versunkene Ruinen*) und nachts an großen tektonischen Void-Spalten der Wiese.
  * Meidet dichte Kronenwälder (bleibt an Bäumen hängen); bevorzugt offene Schneisen, felsige Engpässe und Minenkorridore, in denen er seine Masse als lebendige Barriere einsetzen kann.
* **Rolle im Kampfsystem:**
  * Der **schwere Frontlinien-Koloss, Tank & Raumverdränger**.
  * Bricht die Taktik des simplen Frontalangriffs: Frontale Hiebe prallen an seinem Basaltschild funkensprühend ab. Zwingt Spieler durch weiträumige Flächenbeben (*Ground Slam*) und unaufhaltsame Anstürme (*Bull Rush*) zu flinken Ausweich- und Blinkmanövern in seinen Rücken.
* **Erscheinungsbild, Silhouette & Anatomie:**
  * **Körperbau & Maße:**
    * Gewaltige, vornübergebeugte Hünen-Silhouette. Standhöhe ca. 54–58 px (überragt Ellie mit ihren 42 px deutlich), Rumpfbreite ca. 48 px.
    * 3/4-Top-Down-Squashfaktor 0.78, satter Fußanker bei `(24, 52)`.
  * **Asymmetrischer Hybrid-Bau:**
    * **Der Felskeulen-Arm (Rechts):** Ein gigantischer, kantig verkrusteter Arm aus schwarzem Basalt und scharfkantigen Leerenkristallen (Dicke 8–10 px). Er stützt den Körper beim Gang wie bei einem mächtigen Gorilla ab und dient als verheerende Ramm- und Schlagkeule.
    * **Der Tentakel-Arm (Links):** Drei flexible, pechschwarze Sehnenstränge mit spitzen Dornenklauen. Sie tasten im Moos nach Erschütterungen, halten beim Aufrichten das Gleichgewicht und greifen bei Ausweichmanövern kurz nach dem Spieler.
    * **Der Schildkragen (Front & Schultern):** Massive, dachziegelartig geschichtete Hornplatten (`1a1030` bis `221740`), die Kopf und Brust frontal wie ein Schild wallartig abschirmen.
    * **Die Schwachstelle (Nacken/Rücken):** Zwischen den wuchtigen Schulterhöckern klafft ein tiefer, vertikaler Spalt. Darin pulsiert der **freiliegende Leerenkern** (`b06bff` bis `ecd2ff`) – das ungeschützte Lebenszentrum des Brechers.
  * **Farben & Material-Palette:**
    * Basisfleisch: `07040d` $\rightarrow$ `0e0919` $\rightarrow$ `1a1030` $\rightarrow$ `221740`.
    * Kontur: Ultradunkles Violettschwarz `040208` (1 px).
    * Basalt & Felsplatten: `141221` $\rightarrow$ `292840` $\rightarrow$ `474a6a` $\rightarrow$ `787ea0` (abgestimmt auf die Felsen der Wiese).
    * Rimlight: Kaltes Dunkelviolett `5a36b8` an Kanten und Felsspitzen.
    * Leuchtmaske (Unshaded): Drei kleine magentafarbene Schlitzaugen (`ff4fd8`) tief im Panzervisier; dicke violette Adern (`8a4dff`), die rhythmisch vom Rückenkern in den Felsarm pumpen.
* **Erster Eindruck auf Ellie / Fremde:**
  * Pure physische Urgewalt. Man spürt das Wesen im Zwerchfell, bevor man es sieht – jeder Schritt lässt feine Kiesel tanzen und das Gras erzittern. Der Geruch nach zermahlenem Schiefer, Schwefel und eiskaltem Brunnenwasser schlägt einem entgegen.

---

### 2. Psychologischer Kern (Die innere Mechanik & Zerstörungstrieb)
* **Grundantrieb (Want / Zerstörungstrieb):**
  * **Zermalmung und Einsturz.** Er toleriert keine aufrechten, festen Formen. Mauern, Holzpalisaden, Schilde und Knochen reizen seinen tektonischen Zerstörungsdrang. Er will alles zu flachem Staub schlagen.
* **Tiefstes Bedürfnis (Need):**
  * **Absolute Schwere und Ruhestarre.** Der Brecher leidet unter der kinetischen Last seiner eigenen versteinerten Masse. Er sucht den finalen Zusammensturz – ein In-sich-Zusammensacken, bei dem er wieder zu unbeweglichem Fels erstarren darf.
* **Die Sollbruchstelle (Schwachpunkt & Urangst):**
  * **Der ungedeckte Rückenkern:** Treffer auf den freiliegenden Nackenspalt verursachen **300 % Schaden (dreifacher Multiplikator)** und lösen sofort eine taumelnde Unterbrechung (`State.HURT`) aus.
  * **Trägheit nach dem Bodenschlag:** Trifft der Felskeulen-Arm den Boden, gräbt er sich für knapp eine Sekunde (`RECOVER` 0.95 s) in den Untergrund ein. Der Brecher kann sich währenddessen weder drehen noch wehren – das goldene Angriffsfenster für Ellie und Valdric!
  * **Kollisions-Stun beim Rammstoß:** Wird der Brecher während seines Ansturms geschickt gegen einen massiven Felsen oder dicken Baumstamm gelenkt, prallt er ab und ist für **1.4 Sekunden betäubt**.
* **Der innere Widerspruch:**
  * **Unüberwindbare Front vs. fatale Rückseite:** Nach vorn ein buchstäblicher Monolith, der selbst schwere Schwertstreiche wie Regentropfen abperlen lässt; nach hinten völlig schutzlos ausgeliefert.
* **Verhaltenslogik & Taktik:**
  * Wendet sich nur träge (`turn_speed` 3.5). Versucht, das Ziel stets vor seinem Schildarm zu zentrieren. Droht der Spieler ihn zu umrunden, setzt er zu einem schnellen Fegerhieb an oder stampft rückwärts, um den Rücken an eine Wand zu pressen.

---

### 3. Akustik & Signal-DNA (Die Stimme des Monolithen)
* **Klangbild & Sounddesign:**
  * Tiefe tektonische Sub-Bässe (30–60 Hz), die den Kopfhörer- oder Lautsprecher-Bass fordern.
  * Das mahlende, knirschende Schleifen von Basaltblöcken aufeinander.
  * **Heben des Felsarms (*Charge*, 0.95 s):** Ein tiefes, mahlendes Steinknirschen, untermalt von einem ansteigenden niederfrequenten Brummen.
  * **Einschlag (*Impact*):** Trockener, markerschütternder Knall mit zersplitternden Steingeräuschen.
  * **Rammstoß (*Rush*):** Schabendes Poltern, als würde eine Gerölllawine über Pflastersteine rasen.
  * **Tod:** Ein sattes, hohles Bersten von Steinplatten, gefolgt von zischendem Verflüssigen des Schattenfleisches.
* **Körpersprache & Mikrobewegungen:**
  * **Im Ruhezustand (`IDLE`):** Schweres, wiegendes Aufstützen auf den Felsarm. Das Heben des Rumpfes gleicht dem Atmen eines Berges. Der Rückenkern pulsiert in ruhigem 1.5-Sekunden-Takt.
  * **Beim Aufmerken (`NOTICE`, 0.50 s):** Senkt den Panzerschädel tief zwischen die Schulterplatten, richtet den Felsarm auf und lässt ein dumpfes Bassgrollen hören.
  * **Im Wutanfall / Ladezustand:** Die drei Magentaschlitze im Visier blitzen auf; die dicken violetten Adern am Arm schwellen sichtbar an und glühen unshaded weiß-violett.
* **Telegraphing & Warnflächen:**
  * **Spaltender Bodenschlag:** Roter 120°-Bodenfächer mit satten 54 px Radius. Rote Pixel fließen wie aufbrechende Lava in den Bereich. Aim-Lock friert die Richtung **0.35 Sekunden** vor dem Einschlag ein.
  * **Rammstoß:** Ein 64 px langer, 20 px breiter roter Bodenkorridor.
  * **Bodenbeben:** Beim Aufprall des Felsarms wackelt die Kamera für alle Spieler im Umkreis von 220 px dezent (respektiert Screen-Shake-Settings).
* **Was der Brecher NIE tun würde:**
  * Leichtfüßig hüpfen, an Felskanten emporfedern oder rennen wie ein Tier.
  * Grauen Staub- oder Partikelrauch ausstoßen.
  * Grazile Drehungen vollführen – jede Richtungsänderung erfordert das mühsame Umsetzen seiner tonnenschweren Felsenhand.

---

### 4. Kampfmechanik & Verhaltensdynamiken (Die KI-DNA)
* **Statuswerte & Attribute:**
  * **Lebenspunkte:** **80 HP** (im Vergleich: Spinne 48, Horcher 38).
  * **Grundtempo:** `wander_speed` 10, `chase_speed` 40 (behäbig, aber unausweichlich), `charge_speed` 190 px/s (während des Rammstoßes).
  * **Drehtempo (`turn_speed`):** 3.5 (träge, anfällig für Flankenmanöver).
  * **Knockback-Resistenz:** 0.85. Leichte Hiebe zeigen keinerlei Rückstoß; frontale Treffer erzeugen **keinen Flinch**.
  * **Sichtweite:** 150 px.
* **Trefferzonen-Mechanik (Front vs. Rücken):**
  * **Frontale 180° (Schildpanzer):** Schaden wird um **75 % reduziert** (nur 25 % Nettoschaden). Ladephasen können frontal **nicht** unterbrochen werden.
  * **Hintere 180° (Rückenkern):** Reiner Fleischtreffer verursacht **300 % Schaden**. Schwere Treffer brechen jede Aktion sofort ab und werfen den Koloss in die Stun-Phase (`HURT`, 0.65 s).
* **Vollständiges Moveset:**

| Aktion | Trigger & Distanz | Windup (Aim-Lock) | Ausführung | Recovery | Schaden / Effekt |
|---|---|---|---|---|---|
| **Spaltender Bodenschlag** (*Ground Slam*) | $\le 42$ px Distanz (Hitbox bis 54 px, 120° Bogen) | 0.95 s (Lock bei 0.60 s) | 0.18 s Einschlag | 0.95 s (Arm steckt fest!) | **18 Schaden**, 120 Knockback (schleudert Spieler um!). Erzeugt 3 Schattrisse im Boden. Front ungeschützt von hinten! |
| **Rammstoß** (*Bull Rush*) | 50–130 px Distanz, gerader Pfad | 0.70 s (Lock bei 0.35 s) | 190 px/s Tempo (max. 0.45 s Lauf) | 0.80 s (bei Treffer/Leere) / **1.40 s Stun** (bei Wandkollision) | **16 Schaden**, 140 Knockback. Rammt er gegen feste Bäume oder Felsen, betäubt er sich selbst! Cooldown: 5.0 s. |
| **Abwehrfeger** (*Backhand Sweep*) | Triggert, wenn Spieler $> 1.2$ s im Rücken steht | 0.45 s (schneller Windup) | 0.16 s Drehhieb | 0.65 s | **11 Schaden**, 90 Knockback. Schleudert freche Flankierer zur Seite weg, um die Front wieder auszurichten. |

* **Reaktion auf Schaden & Tod:**
  * **Frontaler Treffer:** Ein sprödes Klingenklirren, winzige grauviolette Funken stieben auf, keine Körperdeformation.
  * **Kerntreffer:** Weißes Aufblitzen des Kerns (`hit_flash`), gewaltiges Aufbäumen, tiefes Schmerzensdröhnen.
  * **Tod:** Bei 0 HP sackt der Koloss auf die Knie. Der Felsarm bricht mit ohrenbetäubendem Krachen vom Rumpf ab und zerfällt in grobe Basaltstücke. Der Weichkörper kollabiert und hinterlässt via `ShadowTrailComponent.infest` einen gewaltigen **10-Tentakel-Schattenfleck**, der 20 Sekunden lang dunkel im Gras nachzuckt.

---

### 5. Lore, Ursprung & Welt-Verflechtung
* **Die Wurzel im Void (Tektonische Entropie):**
  * Der Leerenbrecher entsteht nicht auf leisen Wiesenpfaden, sondern dort, wo die tektonischen Fundamente der Welt brechen – in tiefen Schächten der Mine, an eingestürzten Brücken und uralten Festungswallungen. Er ist die manifestierte Schwere und Verkrustung der Leere.
* **Beute & Ausbeute:**
  * **Erfahrung:** 22 XP (höchster Wert der Standardgegner).
  * **Währung:** 8–18 Kupferstücke.
  * **Materialien:**
    * 85 % Chance: 2–4× **Leersplitter** (`void_splinter`).
    * 25 % Chance: 1× **Schattenkern** (`shadow_core`).
    * 10 % Chance: 1× **Versteinertes Leerenfragment** (`void_slag` / `void_slate`) – seltener, extrem harter Werkstoff für Schildverstärkungen und schwere Rüstungselemente.
* **Beziehung zu den Hauptfiguren:**
  * **Zu Ellie:**
    * Pure Ehrfurcht und Anspannung. Frontal hat Ellie mit ihrem schnellen Schwert gegen den Brecher keine Chance. Sie muss ihren Schatten-Blink und ihre Ausdauer beherrschen, um seinen gewaltigen Schlägen im letzten Augenblick zu entgehen und in seinen Rücken zu hechten.
  * **Zu Valdric:**
    * Valdrics Augen glänzen hinter dem Visier, wenn ein Brecher auftaucht. Hier steht ein Gegner, der Valdrics Ritterehre und Wucht auf die Probe stellt. Valdric kann den Bodenschlag mit gezogenem Schild abfedern, die Aggro halten und Ellie das Kommando zurufen: *„JETZT, ELLIE! SEIN RÜCKEN LIEGT FREI!“*

---

### 6. Voice-Check (In-Game Encounter Momente)

> **Das erste Grollen in der Mine (Witterung & Resonanz):**
> *(Ein tiefes Dröhnen bringt Staub aus der Stollendecke zum Rieseln. Ellie hält inne, die Hand fest am Schwertknauf geklammert.)*  
> **ELLIE:**  
> *(flüstert mit zittriger Stimme)*  
> *„Valdric... sag mir bitte, dass das nur ein herabfallender Felsbrocken war.“*  
> **VALDRIC:**  
> *(senkt ruhig das Visier, zieht mit schwerem Schleifen das Breitschwert)*  
> *„Felsbrocken atmen nicht, Ellie. Mach die Beine locker. Wenn das Ding zuschlägt, stehst du nicht mehr da, wo du gerade stehst.“*

> **Im Gefecht (Der spaltende Schlag):**
> *(Der Brecher bäumt sich auf. Sein steinerner Keulenarm hebt sich hoch in die Luft, dicke violette Adern pumpen gleißendes Licht. Die rote Bodenfläche färbt den Minenboden blutrot.)*  
> **VALDRIC:**  
> *„AUSWEICHEN! Nicht blocken – der Schlag bricht dir die Arme!“*  
> *(Der Felsarm schlägt mit ohrenbetäubendem Donnern ein. Der Boden birst, Steinsplitter fliegen. Der Arm gräbt sich tief in den Schiefer. Der Brecher keucht schwer und steckt fest.)*

> **Der Konter (Ellies Glanzmoment):**
> **ELLIE:**  
> *(blinzelt durch die Staubwolke, sprintet im Bogen hinter die Kreatur)*  
> *„Er rührt sich nicht! Hab dich, du Steinkopf!“*  
> *(Mit beiden Händen stößt sie die Klinge mit voller Kraft in den violett pulsierenden Nackenspalt. Ein blendender Lichtblitz schießt empor, der Koloss stößt ein grollendes Röcheln aus und bricht in die Knie.)*

> **Nach dem Kampf (Valdrics Respekt):**
> **VALDRIC:**  
> *(atmet tief durch, wischt Steinstaub von seiner Schulterplatte)*  
> *„Sauberer Stoß, Kleines. Keine Panik, kein Zögern. Genau so bricht man einen Brecher.“*  
> **ELLIE:**  
> *(lässt die Schultern sinken, stützt sich keuchend auf die Knie und grinst erschöpft)*  
> *„Fast keine Panik. Mein Herz klopft immer noch wie Gustavs Zimmermannshammer... aber wir leben noch. Und der Weg ist frei.“*

---

### 7. Enemy Artist & Rigging Notes (Für Shader- & Modell-Entwickler)
1. **Asymmetrisches Hybrid-Modell:**
   * Der Leerenbrecher verbindet starre, kantige Basaltgeometrie (rechter Arm, Schulterplatten) mit flexiblen, organischen Weichteilen (linker Tentakelarm, Rumpfunterseite, Nackenspalt).
   * Der Felskeulen-Arm muss visuell geerdet wirken: Bei Schrittkontakt muss er auf dem Boden aufsetzen (`foot_landed`), um das schwere Nachschleifen zu vermitteln.
2. **Der Nackenkern als separate Hitbox & Glow-Pass:**
   * Der Kern sitzt bei Offset `(0, -32)` relativ zum Fußanker.
   * Der Kern benötigt eine eigene `HurtboxComponent` oder eine winkelsensitive Trefferabfrage im Hauptskript (`Vector2.from_angle(heading).dot(attack_dir) < -0.2`), um den dreifachen Krit-Schaden zuverlässig auszulösen.
   * Der Kern liegt auf einem separaten additiven Glow-Knoten (`_core_glow`) mit der Farbe `ecd2ff` und pulsiert mit Sinuswelle `sin(_time * 2.5) * 0.2 + 0.8`.
3. **Wandkollision beim Rammstoß (`Bull Rush`):**
   * Während des Ansturms prüft `move_and_slide()` auf Kollisionen mit der World-Ebene (Layer 1). Kollidiert der Brecher mit einem `StaticBody2D` (Felsen, Mauer, Baum), wird der Ansturm sofort abgebrochen und `State.STUN` für 1.4 Sekunden aktiviert.
4. **Kein Partikel-Rauch:**
   * Strenges Verbot von Standard-Graurauch-Emittern! Beim Aufprall des Felsarms werden ausschließlich kantige Pixel-Steinsplitter (`CPUParticles2D`) und Schattrisse (`ShadowTrailComponent`) erzeugt.

---

### 8. Implementierungsstand (2026-11-05)
Vollständig im Spiel: `VoidCrusher` + prozeduraler `CrusherRig`, alle drei Angriffe mit Bodenwarnung und Aim-Lock, Front/Rücken-Schadenslogik (`CrusherHurtbox`), Wandkollisions-Stun, Tod mit abbrechendem Felsarm, Loot (`void_slag` neu), Nacht- und Minen-Spawns, synthetische Audio-Cues (`tools/audio_crusher.py`). Spawn per **F3**; Stundensprung liegt jetzt auf F4. Abweichungen vom Dossier: Rammstoß-Lauf = 64 px (0.34 s, Obergrenze 0.45 s), damit die Warnfläche exakt der Trefferfläche entspricht; Rückentreffer = hintere Halbebene relativ zur Blickrichtung (das Dossier nennt widersprüchlich -0.2). Details: CLAUDE.md, Abschnitt „Void Crusher“.
