# Shadowspore – Das Große Angelsystem: „Atem des Stroms“
*(Master-Konzept: Ökologie, Nacht-Spannung & Siedlungs-Infrastruktur)*

**Status:** Vollständiger Master-Entwurf (Synthese aus Konzept 1, 2 und 3)  
**Systemreferenzen:** `docs/water_design.md`, `docs/water_life.md`, `docs/cooking.md`, `docs/town.md`, `docs/nacht_monster_konzept.md`, `docs/mine.md`, `docs/skill_tree.md`  
**Zielumgebung:** Godot 4.7, GDScript (strict typing), 640×360 Pixelart (16px Raster), 1–4 Spieler Host-Authoritative Co-op  

---

## 1. Vision & Philosophie

### 1.1 Leitgedanke: *Atem des Stroms*
> *„Am Tage liest du das Wasser und nahrst den Stamm. Bei Nacht blickst du in den Schlund und forderst die Leere heraus. Am Steg schließt sich der Kreis aus Licht, Holz und Vorrat.“*

Das Angelsystem in Shadowspore verbindet die drei prägenden Säulen des Spiels zu einem zusammenhängenden Erlebnis:
1. **Das sensorische Naturerlebnis (Tag):** Achtsames Beobachten der echten Wasserströmung, Reaktionen der Ufervögel und natürliches Posen-Driften ohne störende UI-Balken – ganz im Geiste von *„Lies den Kessel“*.
2. **Der existentielle Nervenkitzel (Nacht):** Das **Licht-Dilemma** am Wasser. Seltene Tiefenwesen und versunkene Schätze fordern Fischen in absoluter Finsternis abseits der rettenden Stadtlichter. Der Lärm des Drills lockt nächtliche Schattenwesen an und erfordert asymmetrisches Koop-Teamplay.
3. **Die Siedlungs- & Expeditions-Infrastruktur:** Baubare Stege, Ufer-Lichtpfosten, Reusen und Räuchereien binden den Fluss an die Stadt an. Siedlerin **Maren** automatisiert die Grundversorgung des gemeinsamen Lagers, während Fischöl, Fischleim und Räucherproviant lange Abstiege in die Minen (`mine.md`) ermöglichen.

---

## 2. Die Kern-Mechanik: Das aktive Fischen

Das Angeln findet vollständig **in-world auf dem 640×360-Bildschirm** statt. Es gibt kein separates Fenster und keinen Stardew-Grünbalken.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              DER ABLAUF DES AKTIVEN FANGS                              │
│                                                                                        │
│  1. VORBEREITUNG           2. STRÖMUNGSDRIFT          3. BISSLESEN        4. DRILL     │
│  [Stand & Naturköder] ──► [Driften mit Vektor] ──► [Ringe & Schatten] ──► [Spannung & │
│                           [Zupfen & Schnurgeben]   [Plop & Anschlag]       Fluss]      │
│                                                                               │        │
│                                           5. LANDUNG / CO-OP KESCHERN ◄───────┘        │
│                                           [Prachtexemplar-Bonus]                       │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Vorbereitung: Uferstand, Rute & Naturköder
* **Standplatz-Prüfung:** `WorldRivers.field_at(pos)` unterscheidet trockenes Ufer (`field.x > 0`), seichtes Watwasser (`field.x <= 0`, spritzt leise) und Stege (`surface: "pier"`).
* **Ruten-Hierarchie:**
  - *Eschenrute (Basis):* Aus geschälter Esche und Flachsfaser. Weich, biegsam, dämpft Fluchtstöße ab.
  - *Dornenbiege-Rute (Werkstatt-Ausbau):* Verstärkt mit Knochen und Leerenfaser. Hohe Rückstellkraft für schwere Raubfische.
  - *Glimmweiden-Rute (Marens Meisterstück):* Leuchtet dezent, erhöht Wurfweite und dämpft Wassergeräusche um 35 %.
* **Köder aus der lebendigen Natur:** Keine Dosenware. Köder werden in der Welt gesammelt:
  - *Libelle / Wasserläufer:* Schwimmt oben auf; lockt agile Oberflächenjäger (*Mondforelle*).
  - *Dämmerbeere / Glimmerbeere:* Sinkt taumelnd ab; zieht Schwarmfische (*Silberströmer*) an.
  - *Bachminze / Goldmummel-Knospe:* Lockt pflanzenfressende Stillwasserfische (*Goldbauch-Karpfen*).
  - *Schattenlarve / Glimmkappen-Strunk:* Sinkt auf den Grund; lockt Grundfische (*Kupferkies-Gründling*).
  - *Schattenspinnen-Gespinst:* Spezieller Nachtköder für Leerenwesen; erhöht jedoch den erzeugten Reizwert bei Monstern.

### 2.2 Posen-Treibphase auf echten Strömungsfeldern
* **Zielwurf:** Rechter Stick / Maus platziert eine unaufdringliche, petrol-türkise Zielellipse auf der Wasseroberfläche.
* **Echte Strömungsdrift:** Nach dem Auftreffen mit feinem Wellenring (`WaterRipples.add(pos, 0.45)`) wird die Pose physikalisch vom lokalen Vektorfeld `WorldRivers.flow_at(pos)` erfasst. Sie treibt mit der Strömung, kreist in Kehrwassern hinter Felsen oder verweilt in ruhigen Buchten.
* **Aktive Posenführung:**
  - *Schnur geben (Aktionstaste halten):* Die Pose treibt weit stromabwärts in tiefe Gumpen hinein.
  - *Sanftes Zupfen (Aktionstaste kurz antippen):* Die Pose ruckt 2–3 Pixel stromaufwärts und wirft kleine Ringe. Lockt Raubfische an, verscheucht jedoch scheue Kleinfische bei zu hektischer Bedienung.

### 2.3 Wasserzeichen & der Biss
* **Visuelle & Haptische Hinweise:**
  1. *Fischschatten nähert sich:* Eine dunkle Silhouette löst sich aus dem Kraut oder Flussgrund (moduliert im Wassertiefen-Shader).
  2. *Vor-Ringe & Klopfen:* Die Pose zittert; zwei feine Wasserringe entstehen. Am Controller ist ein dezentes rhythmisches Ticken spürbar.
  3. *Der Schluck (Biss):* Die Pose wird ruckartig unter Wasser gerissen! Ein satter weißer Schaumring bricht auf (`WaterRipples.add(pos, 1.1)`), untermalt von einem hohlen *Plop*.
* **Anschlag:** Anschlag per Aktionstaste innerhalb eines Fensters von 0,8 bis 1,4 Sekunden. Zu früh reißt den Köder heraus; zu spät lässt den Fisch entwischen.

### 2.4 Der Drill: „Spannung & Fluss“ (Kein Stardew-Balken!)
Der Drill ist ein physischer Zweikampf, visualisiert über eine dynamische Bézier-Schnur (`Line2D`) und Shader-Spannung:
1. **Fluchtphase (Fisch flieht stromabwärts):**
   - Die Rute biegt sich tief durch, die Schnur surrt auf.
   - **Spieleraktion:** **Nicht kurbeln!** Dem Zug sanft nachgeben (Richtungstaste/Stick in Zugrichtung neigen, Schnurbremse lockern). Krampfiges Gegenreißen überdehnt die Sehne bis zum Schnurbruch.
2. **Ermüdungsphase (Fisch dreht oder verharrt):**
   - Die Schnur lockert sich und fällt in eine sanfte petrolgrüne Kurve.
   - **Spieleraktion:** **Jetzt ruhig einholen!** Bedächtiges Kurbeln zieht den Fisch heran.
3. **Fluss-Hindernisse:**
   - Zieht der Fisch auf scharfe Felsen oder dichtes Federkraut zu, muss der Angler den Hebelarm der Rute quer zum Hindernis stellen, um die Schnur frei zu halten.

### 2.5 Kooperatives Keschern (Co-op Moment)
* **Die heikle Uferkante:** Im letzten Meter am Ufersaum oder Steg steigt die Bruchgefahr bei kapitalen Fischen (*Glimmerstör*, *Schleier-Aal*) rapide an.
* **Der Kescher-Helfer:** Ein Mitspieler kann mit einem **Handkescher** an die Wasserkante treten. Drückt er im Moment des Heranführens die Interaktionstaste, schöpft er den Fisch sicher an Land!
* **Belohnung:**
  - Garantierte Landung ohne Schnurbruchrisiko.
  - **Prachtexemplar-Status:** Schuppen und Fleisch bleiben unversehrt (+50 % Ertrag an Schuppen/Filet).
  - Gruppen-Buff *„Gemeinsamer Fang“* (+10 % Arbeits- und Baugeschwindigkeit für 5 Minuten).

---

## 3. Die Nacht-Mechanik: Das Schleier-Angeln

Sobald `TimeManager.night_amount() >= 0.3` erreicht, kippt die friedliche Flussatmosphäre in existentielle Spannung.

```
       LICHTKREIS DER BASIS / LATERNE                 DUNKLES, WILDES FLUSSUFER
┌─────────────────────────────────────────┐     ┌─────────────────────────────────────┐
│ • Sicher vor Schattenmonstern           │     │ • Extrem hohe Monster-Gefahr        │
│ • "Lichtdruck" schiebt Feinde weg       │ vs. │ • Schattenwesen pirschen heran      │
│ • Tiefenwesen MEIDEN diesen Bereich     │     │ • Scheue Schattenwesen BEISSEN NUR  │
│ • Nur gewöhnliche Fische beißen         │     │   IN VOLLSTÄNDIGER DUNKELHEIT!      │
└─────────────────────────────────────────┘     └─────────────────────────────────────┘
```

### 3.1 Das Licht-Dilemma (`light_shyness`)
Das Grundaxiom von Shadowspore lautet: **„Licht ist Land“**. Doch unter Wasser verkehrt sich dieser Schutz in ein taktisches Dilemma:
* Gewöhnliche Fische und die friedliche *Glimmer-Schmerle* beißen auch im Licht.
* **Mythische Schattenkreaturen** (*Schleier-Aal*, *Abyssischer Zander*, *versunkene Reliquiare*) besitzen `light_shyness = 1.0`: **Sie beißen ausschließlich in absoluter Finsternis** (`TownManager.light_depth < -32 px`).
* Fällt der Schein einer Fackel oder eines Laternenpfostens auf die Fangstelle, taucht die Beute sofort in die Tiefe ab!

### 3.2 Taktische Posen-Typen
1. **Korkpose (Standard):** Tagsüber optimal, neutral schwimmend.
2. **Glimmkappen-Pose:** Schwaches türkises Glühen (`NightLight`, 18px Radius). Nachts hervorragend sichtbar, lockt neugierige Lichtsucher an, verscheucht jedoch Tiefenwesen. Schützt den Angler **nicht** vor Landkreaturen.
3. **Obsidian-Pose (Dunkelpose):** Völlig lichtlos (`unshaded`, tiefviolette Silhouette). Völlig unsichtbar im Trüben. Der Angler muss rein auf akustische Hinweise (Zupfen) und die Biegung der Rute reagieren. Zwingt zum Fischen im Pechschwarz – schaltet aber die seltensten Fänge frei.

### 3.3 Wasserunruhe & Monster-Reiz (`water_turmoil`)
* Kämpft ein schweres Tiefenwesen im Drill, erzeugt das Peitschen der Sehne und das Platschen im Wasser kontinuierlich **Wasser-Unruhe** (`water_turmoil`).
* Dauert der Drill länger als 10–12 Sekunden, speist das System die Unruhe in den `NightDirector` ein.
* Krabbler (`ShadowSpider`) und Lauscher (`VoidListener`) wittern das Schlagen und brechen aus dem Uferdickicht hervor!
* **Asymmetrisches Koop-Teamwork:**
  - Der Angler ist im Tunnelblick gefangen und kann sein Schwert nicht ziehen.
  - Ein Begleiter sichert mit Waffe und Fackel den Rücken – **muss aber Abstand zum Wasser halten**, um den scheuen Fisch nicht zu vertreiben!

---

## 4. Die Siedlungs-Infrastruktur & Siedlerin Maren

Fischerei ist nicht nur Einzelsport, sondern das Rückgrat der Dorfgemeinschaft (`docs/town.md`).

### 4.1 Baubare Teile im `TownManager` (`data/town.json`)
Das Baumenü erhält die neue Kategorie `water` („WASSERBAU“):

| Bauteil | Fußfläche (px) | Platzierungs-Regel | Kosten | Funktion |
|---|---|---|---|---|
| **Holzsteg-Segment** (`pier_wood`) | 16×32 | `surface: "pier"` (Brücke von Ufer in tiefes Wasser) | 4 Bretter, 2 Stein | Begehbare Plattform über tiefem Wasser; verbindet Siedlungspfade (`TownWays`) mit dem Fluss. |
| **Lichtpfosten am Pier** (`pier_lamp`) | 12×8 | Auf Steg / Uferkante | 4 Holz, 2 Glimmkappen, 1 Seil | Lichtradius 8 Tiles. Bringt „Licht an den Strom“, beruhigt das Wasser, lockt phototaktische Schwärme an. |
| **Fischreuse** (`fish_trap`) | 24×16 | `surface: "shore"` (Flachwasser / Strömung) | 6 Fasern, 3 Holz | Passiver Fangkorb (Kapazität: 5 Fische). Fängt Beifische, Krebse und Knorpelfische. Im Lichtkreis leert Maren sie täglich. |
| **Räucherkammer** (`smokehouse`) | 48×36 | Festes Land, Türzone frei, `paths: true` | 16 Holz, 12 Stein, 2 Lehm | Veredelt Rohfisch zu Räucherproviant und kocht Fischleim. Schornsteinrauch weht mit `WorldWind`. |
| **Hälterungsbecken** (`fish_pond`) | 48×48 | Flaches Land im Lichtkreis | 20 Stein, 8 Holz, 4 Eimer Wasser | Lebendhälterung: Fische verderben nicht. Ermöglicht Zucht seltener Glimmsalmler und Bergkarpfen. |

### 4.2 Die neue Siedlerin: Maren, die Stromhüterin
* **Hintergrund:** Mitte 30, wettergegerbt, gewachster Leinenkittel, Binsenmanschetten, Knochenahle im Gürtel.
* **Einzugsbedingung:**
  1. Siedlungsstufe: **Weiler** (`hamlet`, Stadtfortschritt ≥ 25).
  2. Mindestens ein **Holzsteg** und ein **Lichtpfosten** am Ufer sind fertiggestellt.
  3. Maren trifft mit ihrem Einbaum-Kanu am Steg ein, sobald Licht das Wasser berührt.
* **Tagesroutine (`schedule`):**
  - `05:00 – 07:30 [reusen]`: Läuft die Stege ab, leert alle Reusen im Stadtgebiet ins gemeinsame Lager (`TownStockpile`).
  - `07:30 – 12:00 [raeuchern]`: Befeuert die Räucherkammer, hängt Filets auf und kocht Fischleim.
  - `12:00 – 13:30 [pause]`: Sitzt mit Gustav am Lagerfeuer, tauscht Neuigkeiten aus.
  - `13:30 – 17:30 [netzflicken]`: Sitzt am Stegkopf, flickt Netze und schnitzt Haken (Klopfen/Weben).
  - `17:30 – 21:00 [abendfischen]`: Steht mit langer Rute am Steg; Spieler in ihrer Nähe erhalten einen Konzentrations-Buff.
  - `21:00 – 05:00 [schlaf]`: Schläft in der Steghütte oder Haupthütte.
* **Siedler-Produktion (`produces`):**
  - Verbraucht täglich: 2× Rohfisch + 1× Holz aus dem Stadtlager.
  - Liefert ins Stadtlager: 2× Räucherfisch + 1× Fläschchen Fischöl.
* **Marens Werkstatt & Waren (`maren_dock` in `data/shops.json`):**
  - *Wathosen (`river_waders`):* Verhindern Verlangsamung und Nässe-Kälte in seichten Flussfurten.
  - *Gewachste Seidenschnur:* Reißt 40 % seltener bei Überlastung.
  - *Binsenfloß (`reed_raft`):* Tragbares 1-Tile-Floß zum Erreichen einsamer Flussinseln.

---

## 5. Beute, Wirtschaft & System-Synergien

### 5.1 Charakteristische Fänge der Gewässer

| Fisch / Beute | Habitat & Tiefe | Aktivität | Besonderheit im Drill | Nutzen & Synergie |
|---|---|---|---|---|
| **Silberströmer** | Seichte Kiesbänke (`field.y < 0.35`) | Tag | Flink, kurze Fluchten, ermüdet schnell | Basis-Speisefisch, zarter Kesselsud |
| **Kupferkies-Gründling** | Strömungsschatten hinter Felsen | Tag | Stemmt sich stur auf den Grund | Hoher Fischöl-Ertrag, erdig-mineralisch |
| **Mondforelle** | Gumpen unter Wasserfällen | Dämmerung / Tag | Springt im Schaum, kämpft mit Strömung | Gourmet-Filet für *„Flussläufer-Atem“* (Tempo im Wasser) |
| **Goldbauch-Karpfen** | Ruhige Buchten unter Linsenteppichen | Tag | Träges Schwergewicht, zieht ins Kraut | Ideal für sämige Fonds und Fischleim |
| **Glimmer-Schmerle** | Seichte Ufer im Laternenlicht | Nacht | Zappelig, glimmt sanft türkis | Zutat für Lichttränke; Köder für Tiefenräuber |
| **Schleier-Aal** | Tiefste Kolke (`field.y > 0.8`) | Nacht (nur Dunkelheit!) | Mächtige Sinuswellen, sucht Felsspalten | *Schleier-Haut* (Rüstung), Sud verleiht *Nachtsicht* |
| **Abyssischer Zander** | Tiefe Seen & dunkle Becken | Nacht (nur Dunkelheit!) | Brutale Stöße, erzeugt hohe Wasserunruhe | *Panzerkamm* für Klingen, *Reine Schatten-Essenz* |
| **Lebender Schatten-Polyp** | Tiefe Nachtrisse im Fluss | Nacht (Gefahr!) | Wirbelndes Gewicht, spritzt beim Fang | Materialisiert als Mini-Monster am Ufer; lässt *Polypen-Nektar* fallen |
| **Versunkene Schatulle** | Flussgumpen & versunkene Ruinen | Immer | Totes, extremes Schwergewicht | Seltene Minenerze, antike Baupläne für Stadtlaternen |

---

### 5.2 Synergie 1: Kochen („Lies den Kessel“, `docs/cooking.md`)
Fisch bereichert das Kesselsystem um völlig neue geschmackliche Dimensionen:
* **Drei Handgriffe mit Fisch:**
  1. *Basis:* Sanft in Minzen-Öl anschwitzen (samtig), kräftig anbraten (rauchig) oder im Quellwasser aufsetzen (leicht).
  2. *Gartakt (Geschicklichkeitsmoment):* Fischfilet im richtigen Siedemoment hineingleiten lassen (golden = glasig zart, ungenau = zerfällt und trübt den Fond).
  3. *Abschluss:* Vom Feuer ziehen (frisch), sanft fertigziehen (rund) oder zur Glace einkochen (intensiv).
* **Meistergerichte & Wirkungen:**
  - *Mondforellen-Kesselsud:* Verleiht 15 Minuten lang *„Flussläufer-Atem“* (Wasser durchqueren kostet keine Ausdauer, +20 % Tempo).
  - *Würzige Schmerlen-Pfanne:* Verleiht 10 Minuten lang *„Leeren-Resistenz“* (-15 % Schattenschaden, Schutz vor Minenkälte).
  - *Schleier-Aal-Eintopf:* Verleiht *„Nachtsicht“* (Augenpaare lauernder Monster am Bildschirmrand leuchten doppelt so weit im Nebel auf).

### 5.3 Synergie 2: Vorrat & Mine (`docs/mine.md`)
* **Verderb & Haltbarkeit:** Frischer Fisch verdirbt nach 2 Ingame-Tagen zu Fischabfall (Dünger).
* **Veredelter Proviant:**
  - *Räucherfisch:* Dauerhaft haltbar; heilt 25 LP und spendet *„Satte Wärme“* (dämpft Kälte- und Erschöpfungsaufbau in Schacht 2 und 3 der Mine).
  - *Stockfisch:* Extrem leicht, stapelbar bis 50 Stück; das ideale Notfallbrot für lange Dungeon-Expeditionen.
* **Industrielle Handwerksstoffe:**
  - *Fischöl / Knorpeltran:* Brennstoff für Stadtlaternen und Handlampen (+25 % Lichtradius; schlägt Schattenmonster zuverlässig zurück) sowie Schmiermittel für Minen-Aufzugswinden.
  - *Fischleim:* Bindemittel für Gustav, um wetterfeste Schindeldächer und große Lagerkisten zu zimmern.
  - *Panzerschuppen:* Für Knochenpfeile und wasserabweisende Schuppenrüstungen.

### 5.4 Synergie 3: Das Schleiergeflecht (`docs/skill_tree.md`)
Seltene Fänge liefern **Schleier-Essenzen**, die im Fähigkeitenbaum als Katalysatoren für passive Schatten- und Naturperks dienen:
* *„Tiefenohr“:* Unterwasser-Risse werden als feine Lichtwirbel durch den Nebel hindurch hör- und sichtbar.
* *„Schattenfaden“:* Verringert die Zerrkraft kämpfender Fische um 25 % und erhöht die Schnurreißgrenze.
* *„Nachtwandler-Aura“:* Verringert die Entdeckungsreichweite durch Krabbler, während man regungslos am Ufer kniet.

---

## 6. Technische Architektur in Godot 4.7

### 6.1 Datenverträge (`res://data/`)
1. **`data/fishing.json`:**
   - `rods`: Ruten-Definitionen (Biegsamkeit, Schnurstärke, Reichweite, Geräuschdämpfung).
   - `baits`: Köder-Eigenschaften (Sinkrate, Duftradius, Zielarten, Reizfaktor).
   - `species`: Fischarten (Tiefe, Tag/Nachtfenster, `light_shyness`, Zugkraft, Ausdauer, Beute-Items).
2. **`data/town.json`:**
   - Erweiterung um Kategorie `water` mit `pier_wood`, `pier_lamp`, `fish_trap`, `smokehouse`, `fish_pond`.
3. **`data/settlers.json`:**
   - Vollständiger Eintrag für `maren` (Bedingungen, Routen, Dialoge, `produces`).
4. **`data/items.json`:**
   - Werkzeuge (`rod_basic`, `rod_hardened`, `rod_maren`, `landing_net`).
   - Fische (`fish_minnow`, `fish_trout`, `fish_loach`, `fish_carp`, `fish_eel`, `fish_pike`).
   - Rohstoffe (`fish_oil`, `fish_glue`, `dusk_scales`, `smoked_fish`, `dried_fish`).

### 6.2 Host-Authoritative Replikation (Multiplayer)
* **Zustandsmaschine (`FishingState`):**  
  `IDLE` → `AIMING` → `CASTING` → `DRIFTING` → `NIBBLE` → `HOOKED` → `DRILL` → `LANDED` / `SNAPPED`
* **RPC-Protokoll:**
  - Client meldet Wurfabsicht via `InputManager`:  
    `@rpc("any_peer", "call_local", "reliable") func request_cast(target: Vector2, bait: String)`
  - Host validiert Position gegen `WorldRivers` und ermittelt Anbiss-Wahrscheinlichkeit anhand von `RiverFauna`-Nähe und Tageszeit.
  - Drill-Physik (Spannung, Zerrkraft, Fischwinkel) läuft host-autoritativ; Server synchronisiert Spannungsstatus und Posenvektoren mit 20 Hz an die Peers.
  - Helfer sendet `@rpc func request_net_assist()` – Host prüft Abstand zum Fisch und gewährt Prachtexemplar-Status.

### 6.3 Shader & visuelle Effekte
* **`river_water.gdshader` Anbindung:**
  - Die Pose speist ihre Position in das Uniform-Array `uniform vec4 disturbances[8]` ein.
  - Drift erzeugt sanfte Ringe (`disturbances[i] = Vector4(pos.x, pos.y, 8.0, 0.25)`).
  - Drill-Turbulenz erzeugt schäumende Schaumwirbel (`disturbances[i] = Vector4(pos.x, pos.y, 26.0, 0.85)`).
* **Dynamische Angelschnur (`Line2D` mit `fishing_line.gdshader`):**
  - Schnurfarbe interpoliert stufenlos: Petrolgrün (`3cc0c6`, locker) → Gold (`e6c468`, optimal) → Magenta/Rot (`ff4a63`, Zerreißgefahr mit feinem Zitter-Shader).

---

## 7. Zusammenfassung des Spielerlebnisses

Mit dem Gesamtsystem **„Atem des Stroms“** erhält Shadowspore eine perfekte Balance aus drei emotionalen Zuständen:
1. **Entspannung & Naturverbundenheit:** Am sonnigen Nachmittag am Flussufer stehen, die Libellen beobachten, den Strömungsdrift genießen und frische Forellen für den abendlichen Kessel fangen.
2. **Hochspannung & Koop-Adrenalin:** Bei Mitternacht im Stockdunkeln die Obsidian-Pose in den tiefen Kolk werfen. Wenn der Schleier-Aal anbeißt und das Wasser peitscht, pirschen Schattenspinnen heran – während der Mitspieler mit gezogener Klinge die Finsternis abwehrt.
3. **Stolz auf den Siedlungsfortschritt:** Zu sehen, wie Stege und Lampen das Ufer erleuchten, Maren morgens die Reusen leert, aus der Räucherkammer aromatischer Rauch weht und die Gruppe mit geräuchertem Proviant und Fischöl-Laternen bestens gerüstet in die tiefsten Minenschächte aufbricht.
