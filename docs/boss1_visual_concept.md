# Shadowspore – Visuelles Design & Rigging-Konzept: 1. Boss (Leerenschwinge)

Dieses Dokument definiert das visuelle Design, die Silhouette, Anatomie, Posen, die Säulen-Architektur sowie das prozedurale Rigging für den 1. Boss von *Shadowspore*.
Es folgt strikt den Art-Richtlinien aus [design_guide.md](design_guide.md) und der Leerenwesen-Biologie (`VoidGlow`, `ShadowTrailComponent`, `shadow_patch.gdshader`).

---

## 1. Silhouette, Proportionen & Anatomie

### 1.1 Leitmotiv & Wirkung
Kein generischer Drache, keine klassische Fledermaus. Der Boss – **Die Leerenschwinge** (*Corvus Vorax / Die Schattenschwinge*) – ist ein uraltes, vogelartiges Raubwesen aus zähflüssigem, sehnig verdichtetem Void-Fleisch und verkrustetem Basaltgestein.
Seine Präsenz schwankt zwischen der **regungslosen Bosheit einer gotischen Wasserspeier-Statue** beim Thronen auf den Säulen und der **schneidenden Härte eines Raubvogels** im Sturzflug.

### 1.2 Anatomische Schlüsselmerkmale
- **Kranium & Schnabelspalt:**
  - Länglicher, vogelartiger Raubvogelschädel ohne Augenhöhlen im klassischen Sinn.
  - Hornig-mineralisierter Oberschnabel aus pechschwarzem Basalt (`0d0a17` bis `262440`).
  - Ein dreifach vertikal gekammertes Schläfenareal mit jeweils **3 schmalen, übereinander liegenden Magentaschlitzen** (`ff4fd8`) pro Kopfseite (insgesamt 6 Augen).
  - Der Schnabel öffnet sich nicht rein mechanisch über ein Kiefergelenk, sondern reißt als fleischiger Spalt mit sichtbaren violetten Sehnenfäden auf.
- **Rumpf & Hängebrust:**
  - Schmaler, extrem vornüber gebeugter Thorax mit hervortretendem, knöchernem Brustbeinkamm (Kiel).
  - In der Brustbeinsenke liegt der **Resonanz-Void-Kern** frei: eine pulsierende, eiförmige Energieblase, die von rippenartigen Hornspangen umfasst wird.
  - Rückgrat mit spitzen, dachziegelartig überlappenden Hornfortsätzen.
- **Schwingen (Klingen-Lamellen & Void-Membranen):**
  - Zweigliedriger Schwingenarm (Humerus ca. 16 px, Radius/Ulna ca. 18 px) aus faserigem Schwarzfleisch.
  - Keine glatte Fledermaushaut: Die Tragfläche besteht aus **segmentierten, dolchartigen Klingen-Federn** (6 Primärfedern, 5 Sekundärfedern je Flügel).
  - Die Federn sind mineralisierte Hornklingen, verbunden durch dehnbare, tiefviolette Fleischmembranen.
  - Im gefalteten Zustand schieben sich die Klingen wie ein Fächer / Lamellenpanzer übereinander; im Flug fächern sie auf und erzeugen eine aggressive, gezackte Silhouette.
  - An den Flügelunterkanten und den Flanken hängen **4–6 schleifende Schattenstränge** (Void Tendrils, 12–20 px lang), die im Flug physikalisch nachwehen und bei Boden-/Säulenkontakt zischend dunkle Spuren ziehen.
- **Greifkrallen & Läufe:**
  - Kräftige, sehnige Vogelbeine mit rückwärts gekrümmten Kniegelenken.
  - Vier massive Spreizzehen (drei nach vorn, eine opponierbare Hinterzehe) mit dolchartigen Basaltkrallen (je 6–8 px lang).
  - Entwickelt, um die Kanten der monolithischen Säulenkapitelle formschlüssig zu umklammern und sich förmlich in das Gestein einzugraben.

### 1.3 Maßstab & Dimensionen (640×360 Canvas, 16-px-Raster)
- **Referenzgrößen:**
  - Spielerin Ellie: Standhöhe **42 px** (Frame 48×56).
  - Leerenbrecher (*Crusher*): Standhöhe **56 px**, Breite ca. 48 px.
- **Boss-Abmessungen:**
  - **Sitzhöhe auf der Säule (Perch Pose):** **46–49 px** (kompakt geduckt, Glockenform, Breite an der Basis ca. 34 px).
  - **Spannweite im Gleitflug:** **78–88 px** (Körperbreite ca. 18–20 px, jede Schwinge ca. 30–34 px).
  - **Körperlänge im Flug (Schnabel bis Krallenspitze):** **54–58 px**.
  - **Bodenschatten-Ellipse:** **36×14 px** (im Flug auf Bodenebene projiziert, 28 % Deckkraft).
  - **Flug-Elevation:** Sprite angehoben auf Höhenversatz `Y = -48 px` bis `-68 px`, logischer Z-Index = `5`.

---

## 2. Farb- & Beleuchtungs-DNA

Strikte Übereinstimmung mit `docs/design_guide.md` (Zeile 44–45) und `VoidGlow.gd`:

```
               [1 px Kontur: #040208]
   +-----------------------------------------------+
   |   Basisfleisch (World-Lit):                   |
   |   Tiefstes Schattenfleisch:      #07040d      |
   |   Mittlere Muskelfasern:         #0e0919      |
   |   Erhabene Sehnen / Gewebe:      #1a1030      |
   |   Gewebe-Highlights:             #221740      |
   |   Basalt-Klingen & Krallen:      #0d0a17 ->   |
   |                                  #171526 ->   |
   |                                  #262440 ->   |
   |                                  #45436a      |
   |   Kaltes Rimlight (links oben):  #5a36b8 /    |
   |                                  #6a3fd0      |
   +-----------------------------------------------+
   |   Unshaded Emission (VoidGlow - Additive Pass):|
   |   Augenschlitze (3x2):           #ff4fd8      |
   |   Augen-Glanzkern:               #fff7ff      |
   |   Flügeladern / Puls:            #7d57e0      |
   |   Adern-Peak:                    #a98af0      |
   |   Resonanz-Void-Kern:            #ecd2ff      |
   |   Kern-Aura (Bloom):             #b06bff      |
   +-----------------------------------------------+
```

### 2.1 Schattierungs- & Lichtregeln
1. **Kein grauer Rauch, keine weichen Nebelpartikel:** Das Wesen dampft nicht. Substanzverlust zeigt sich ausschließlich durch abtropfende zähe Void-Perlen, zerberstende Void-Splitter (`assets/fx/shard.png`) und den Bodenbefall (`ShadowPatch`).
2. **World-Lit Gewebe:** Der Rumpf und die Flügeloberflächen werden normal vom `CanvasModulate` (`DayNight`) mitgetönt. Nachts wird das Gewebe tiefschwarz-violett; tagsüber zeichnen sich die sehnigen Muskelstränge plastisch ab.
3. **Unshaded Leuchtmaske (`VoidGlow`):**
   - **Augen:** 6 magentafarbene Pixelpunkte (`ff4fd8`) mit `VoidGlow.halo(..., bloom=0.8)`. Blicken starr auf das Ziel.
   - **Flügeladern:** Verästelte Linien (`VEIN` = `7d57e0`, `VEIN_LIGHT` = `a98af0`), die vom Rücken über die Flügelknochen bis in die Ansätze der Klingen-Federn laufen. Sie tragen den zweistufigen Herzschlag (`VoidGlow.beat(time, -dist * 0.012, rate)`).
   - **Kehlkern:** Großer Glühbereich mit weißem Zentrum (`fff7ff`/`ecd2ff`) und breiter violetter Aura (`b06bff`, `bloom=1.2`). Vor dem Start oder bei Schreien schwillt die Leuchtkraft um 60 % an.

---

## 3. Posen & Rigging-Konzept

Das Wesen wird – analog zu `CrusherRig` und `ListenerRig` – als **prozedurales / mehrschichtiges 2.5D-Pixel-Rig** in Godot implementiert. Keine starren Rotationen von vorgerenderten Bitmaps, sondern eine dynamische Knochenkette mit 3/4-Perspektivenprojektion (`SQUASH = 0.76`).

```
                    Hintere Schwinge (Back Wing)
                               |
               Hintere Greifkralle (Back Talon)
                               |
                        Hauptrumpf & Kiel
                       /                 \
        Hals & Kopfspalt              Resonanz-Void-Kern
        (Magentaschlitze)             (Additive Glow Layer)
                       \                 /
               Vordere Greifkralle (Front Talon)
                               |
                    Vordere Schwinge (Front Wing)
                               |
               Schleifende Stränge (Trailing Tendrils)
```

### 3.1 Pose A: Thronend auf der Säule (Perch Pose / "Gargoyle-Glocke")
- **Gestalt:**
  - Rumpf tief geduckt; das Brustbein senkt sich fast auf das Säulenniveau ab.
  - Die beiden Schwingen sind nach vorn-unten geschlossen gefaltet und hüllen den Rumpf wie ein **zerschlissener, panzerartiger Mantel** ein.
  - Die Klingen-Federn bilden eine sich nach unten verbreiternde Glockensilhouette (oben 18 px Schulterbreite, unten 34 px Fächerbreite). Die untersten Federspitzen berühren das Gestein.
  - Die beiden gewaltigen Krallen liegen weit vorne auf der Rundung des Säulenkapitells; die 1 px spitzen Krallenenden greifen 2 px über die Kante hinab.
- **Lebendigkeit:**
  - Sehr langsames, schweres Atmen (`0.35 Hz` Sinus-Hebung des Rumpfes um 1–2 px).
  - Der Kopf ist nach vorn gereckt und blickt leicht nach unten geneigt direkt zur Arena-Mitte / Spielerin.
  - Hinter den Schlitzen des Schwingenmantels schimmert das rhythmische Pulsieren des Kehlkerns hervor.
  - Alle 2,5 bis 4 Sekunden löst sich ein zäher Void-Tropfen von einer Schwingenspitze und fällt senkrecht an der Säule herab.

### 3.2 Pose B: Flug-Silhouette & Präsentation
- **Gestalt:**
  - Schwingen voll auf 84 px Spannweite entfaltet. Leicht schräg nach vorn in den 3/4-Raum geneigt.
  - **Dynamischer Flügelschlag:** Kein starres Auf- und Abklappen. Die Bewegung läuft als Welle: Schultergelenk hebt sich zuerst, der Ellbogen folgt mit 0,08 s Verzögerung, die Klingen-Federn biegen sich beim Aufwärtsschlag flexibel durch (Auffächern) und verriegeln sich beim kraftvollen Abwärtsschlag zu einer fast ebenen Schnittkante.
  - **Schattenstränge:** 4 fingerdicke Void-Tentakeln hängen von Unterleib und Flügelkanten herab. Sie folgen einer Trägheits-Physik (Verzögerung mit 12 Segmenten) und bilden wehende, geschwungene Bänder im Flugwind.
  - **Beine:** Krallen sind aerodynamisch nach hinten-oben unter den Rumpf angewinkelt, die Krallenspitzen leicht geöffnet.
- **Flug-Präsentation im 2D-Raum:**
  - Der Node-Ursprung (`global_position`) wandert auf dem realen Arenaboden entlang (hier greifen Kollision und Y-Sortierung).
  - Anker am Boden: Eine flache, weiche Bodenschatten-Ellipse (`36×14 px`), die über den Boden gleitet.
  - Der visuelle Boss-Körper (`VisualBody`) wird über einen internen Höhenversatz (`flight_height = 54.0`) vertikal nach oben verschoben.
  - Sobald der Boss die Säule verlässt, springt sein `z_index` von `0` auf `5`, sodass er glaubhaft über Säulenschäften, Bäumen, Geschossen und Ellie hinwegfliegt.

### 3.3 Pose C: Start & Landung (Takeoff & Perch Land)
- **Start-Ablauf (Dauer ca. 0.85 s):**
  1. *Spannung (0.00 – 0.35 s):* Krallen krallen sich tief in den Stein. Der Körper duckt sich noch tiefer (Kompression auf 75 % Höhe). Die Schwingen reißen ruckartig weit nach hinten-oben auf; der Kehlkern flammt blendend weiß auf.
  2. *Abstoß (0.35 – 0.45 s):* Krallen stoßen den Säulenkranz ab. Feine Basaltsplitter fliegen weg.
  3. *Schlag & Auftrieb (0.45 – 0.85 s):* Ein gewaltiger erster Abwärtsschlag der Schwingen katapultiert das Wesen vertikal nach oben. Die Schattenstränge peitschen nach. Übergang in horizontalen Streckenflug.
- **Lande-Ablauf (Dauer ca. 0.70 s):**
  1. *Bremsfächer (0.00 – 0.40 s):* Das Wesen kippt den Rumpf in der Luft fast senkrecht auf; die Schwingen stellen sich frontal gegen die Flugrichtung und fächern weit auf. Die Krallen greifen weit nach vorn aus.
  2. *Aufschlag & Krallenbiss (0.40 – 0.52 s):* Die Krallen schlagen mit voller Wucht auf das Säulenkapitell. Kamera-Impuls (`ScreenShake` ca. 1.8 px, harter Bass-Knall). Krallen hinterlassen zischende schwarze Rissspuren auf dem Stein.
  3. *Einfedern & Einmantelung (0.52 – 0.70 s):* Der Rumpf federt tief ein (Squash). Die Schwingen klappen mit einem raschelnden, schabenden Geräusch wieder eng um den Körper zusammen.

---

## 4. Visuelle Gestaltung der 3 Säulen

Die 3 Säulen sind uralte, monolithische Kult-Pfeiler, die das Boss-Areal dominieren und ein Dreieck bilden.

```
       [Kapitell / Sitzkrone: 38 px breit]
     +---------------------------------------+
     |  ###   Kratzspuren & Void-Krusten ### |
     +---\                               /---+
          \                             /
           |  Verwitterter Basalt      |
           |  Moosflecken (#2f624e)    |
           |  Schaftbreite: 30 px      |
           |  Höhe sichtbar: 76 px     |
           |                           |
           |  Herablaufende zähe       |
           |  Void-Tropfnasen          |
           |                           |
     +-----/                           \-----+
     |  Bodenbasis: Felsquader & Geröll      |
     +---------------------------------------+
```

### 4.1 Abmessungen & Geometrie
- **Sichtbare Höhe:** **76 px** (entspricht fast zwei Spielerhöhen; Ellie wirkt am Fuß der Säule klein und verwundbar).
- **Schaftbreite:** **30 px** im Mittelteil, leicht tailliert.
- **Sitzkrone (Kapitell):** Oben aufgeweitet auf eine flache, polygonale Plattform von **38×16 px** (in 3/4-Perspektive abgeflacht). Bietet exakt genug Standfläche für die gespreizten Krallen des Bosses (Spurbreite ca. 28–32 px).
- **Kollision:** Kreisförmige / ovale Sperrkollision am Säulenfuß (`Vector2(26, 14)` px), Y-sortiert an der Basiskante.

### 4.2 Materialität & Farbwerte
- **Basaltgestein:** Palette aus verwittertem, rissigem Fels (`0d0a17`, `171526`, `262440`, diffuse Lichtkante links oben `45436a` / `6b6894`).
- **Pflanzlicher Bewuchs:** Flecken aus trockenem und kaltem Moos (`22483c`, `2f624e`), das an den oberen Kanten durch die Krallenbeanspruchung weitgehend abgewetzt ist.
- **Void-Kontamination & Verwitterung:**
  - **Krallen-Riefen:** An den Kanten des Kapitells befinden sich tief eingekerbte, parallele Furchen (`040208`), aus denen nachts feine violette Adern glimmen.
  - **Tropfnasen:** An den Säulenseiten laufen erstarrte, wulstige Tropfenbahnen aus tiefschwarzem Void-Schleim herab (ähnlich wie geronnenes schwarzes Pech, getönt in `07040d` und `1a1030`).
  - **Säulenfuß:** Am Boden sammelt sich abgeplatztes Steingeröll, durchsetzt mit kleinen Rissen, die ins Gras übergehen.

---

## 5. Todesauflösung (Death Dissolution)

Der Tod des Bosses ist ein physischer Kollaps in 4 inszenierten Phasen ohne Rauchwolken:

```
+-----------------------------------------------------------------------------+
| Phase 1: Kernüberladung (0.0s - 0.7s)                                       |
| - Kehlkern flammt im Stakkato grell auf (14 Hz, #fff7ff).                  |
| - Klingen-Federn verkrampfen und bersten in 8-12 Void-Splitter.             |
+-----------------------------------------------------------------------------+
                                     |
                                     v
+-----------------------------------------------------------------------------+
| Phase 2: Der Absturz (0.7s - 1.3s)                                          |
| - Krallen verlieren Halt / Flügel versagen.                                 |
| - Taumelnder Sturzflug Richtung Arenaboden; Z-Offset sinkt auf 0.          |
+-----------------------------------------------------------------------------+
                                     |
                                     v
+-----------------------------------------------------------------------------+
| Phase 3: Aufprall & Gewebekollaps (1.3s - 2.0s)                             |
| - Wuchtiger Aufprall am Boden (ScreenShake, Knirschen).                    |
| - Basaltpanzer zerschellt; Rumpf verliert Zusammenhalt und verflüssigt sich.|
+-----------------------------------------------------------------------------+
                                     |
                                     v
+-----------------------------------------------------------------------------+
| Phase 4: Massiver 12-Tentakel-Schattenbefall (2.0s - 24.0s)                 |
| - Riesiger Kontaminationspool (84x56 px) via ShadowPatch.                  |
| - 12 zuckende Void-Tentakeln (arms=12) fressen den Untergrund.             |
| - 3 Satellitenflecken um den Kern; Implosion hinterlässt Boss-Loot.        |
+-----------------------------------------------------------------------------+
```

### 5.1 Detailphasen des Todes
1. **Kernüberladung & Flügelbersten (0.0 – 0.7 s):**
   - Das Wesen erstarrt in der Luft oder bäumt sich auf der Säule auf.
   - Der weiße Resonanzkern in der Brust überlädt sich: hektisches Stakkato-Blinken (14 Hz) zwischen Weiß (`fff7ff`) und stechendem Magenta (`ff4fd8`).
   - Die Klingen-Federn splittern ab: 8 bis 12 harte, eckige Partikelsplitter fliegen radial weg und trudeln trudelnd nach unten.
2. **Der physische Absturz (0.7 – 1.3 s):**
   - Befindet sich der Boss auf der Säule, kippt er unkontrolliert vornüber über die Kante. Befindet er sich im Flug, trudelt er mit gelähmten Schwingen trudelnd zu Boden.
   - Der Höhenoffset (`flight_height`) wird entlang einer beschleunigten Parabel auf `0.0` reduziert.
3. **Aufschlag & Verflüssigung (1.3 – 2.0 s):**
   - Das Wesen schlägt mit vollem Gewicht auf der Wiese auf.
   - Heftiger Kamera-Stoß (`ScreenShake` ca. 2.5 px).
   - Das knöcherne Gewebe kollabiert: Das Fleisch verliert augenblicklich seine Festigkeit und zerfließt wie teerartige Tinte in die Grasnarbe.
4. **Massiver 12-Tentakel-Befall (`ShadowTrailComponent` & `ShadowPatch`):**
   - An der Aufprallstelle wird ein riesiger Hauptbefall erzeugt:
     - `size = Vector2i(84, 56)` px.
     - `arms = 12` (Tentakel-Anzahl, die kriechend und pulsierend über das Gras zucken).
     - `life = 14.0 s`, `fade = 8.0 s`.
   - Um den Hauptpool entstehen 3 versetzte Satelliten-Befallspools (`Vector2i(28, 20)`, je 4 Tentakeln).
   - Zuletzt kollabiert der weiße Restkern mit einem kleinen, scharfen Lichtblitz zu Boden und gibt die Beute frei (*Leerensplitter, Boss-Essenz*).

---

## 6. Technische Rig-Struktur (Godot 4.7 Node-Hierarchie)

```gdscript
WingedBoss (CharacterBody2D)
├── CollisionShape2D (Bodenkollision / Füße: Kreis r=12)
├── HurtboxComponent (Körperkern: Rect 24x28 bei Y=-20)
├── ShadowTrailComponent (Befall bei Schritten/Landung & Tod)
├── Shadow (Sprite2D / CanvasItem: 36x14 Ellipse, Modulate a=0.28, Z=0)
└── VisualRig (Node2D, Y-Offset gesteuert durch flight_height)
    ├── BackWings (Node2D, draw: hinterer Schwingenarm & Klingen)
    ├── BackTalon (Node2D, draw: hintere Kralle am Stein)
    ├── Torso (Node2D, draw: Thorax, Hornrückgrat, sehniges Fleisch)
    ├── Head (Node2D, draw: Schnabelspalt & Basaltkranium)
    ├── FrontTalon (Node2D, draw: vordere Greifkralle)
    ├── FrontWings (Node2D, draw: vorderer Schwingenarm & Klingen)
    ├── Tendrils (Node2D, draw: 4-6 schleifende Void-Stränge)
    └── GlowPass (Node2D, CanvasItemMaterial: BLEND_MODE_ADD, unshaded)
        ├── EyeGlow (6 Magentaschlitze via VoidGlow.halo)
        ├── VeinGlow (Pulsierende Flügeladern via VoidGlow.beat)
        └── CoreGlow (Resonanz-Void-Kern in der Kehle via VoidGlow.halo)
```

Mit dieser Spezifikation ist das Boss-Wesen visuell unverwechselbar, fest in der DNA von *Shadowspore* verankert und bietet dem Rigging- und Animationsteam eine exakte Pixel- und Strukturvorlage.
