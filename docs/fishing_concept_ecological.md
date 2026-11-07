# Lies das Wasser – Ökologisches & Sensorisches Angeln in Shadowspore

> **Konzept:** Ökologisches & Sensorisches Angeln (Ökosystem, Strömung & achtsamer Rhythmus)  
> **Konzepter:** Konzepter 1 – Systemdesign, Ökologie & Kesselsynergie  
> **Bezug:** Ergänzung zu `docs/water_design.md`, `docs/water_life.md`, `docs/cooking.md` und `src/water/`  
> **Status:** Vollständiger Konzeptentwurf für Shadowspore (Godot 4.7, 640×360, Host-Authoritative Co-op)

---

## 1. Kernvision & Philosophie

### 1.1 Name des Systems: *Lies das Wasser*
In direkter Verwandtschaft zu unserem Kochsystem **„Lies den Kessel“** folgt die Fischerei keinem nervösen Reaktionsmuster oder isolierten Balken-Minispiel, sondern der aufmerksamen Wahrnehmung der Welt: **„Lies das Wasser“**.

Das Gewässer in Shadowspore ist keine statische Kulisse mit aufgesetztem Zufallsgenerator. Es ist ein physikalisch fundiertes, strömendes und atmendes Ökosystem. Wer die Wasseroberfläche beobachtet – die feinen Doppelringe scheuer Fische, den Schattenwurf unter treibendem Federkraut, das Aufwirbeln von Grundschlamm durch gründelnde Enten oder das plötzliche Schweigen der Reiher –, begreift das Gewässer intuitiv und weiß, wo die Sehne ins Wasser gleiten muss.

### 1.2 Warum es sich 100% nach Shadowspore anfühlt
1. **Achtsamkeit statt Quick-Time-Event**: Kein hektisches Button-Mashing, kein künstlicher Stardew-Grünbalken. Das Einholen ist ein haptischer, rhythmischer Dialog zwischen der Strömung des Flusses, den Fluchtstößen des Fisches und der Biegung einer Eschenrute.
2. **In-World-Immersion auf 640×360**: Das Angeln findet direkt in der Top-Down-Spielwelt statt. Keine Unterbrechung durch bildschirmfüllende Overlays; die Heldin steht am sandigen Ufersaum, die Seidenschnur wirft feine Glanzlichter im kühlen Petrol des Wassers, und der Fisch kämpft sichtbar zwischen Unterwassersteinen und Wasserpflanzen.
3. **Farbharmonie & Mystik**: Gedämpftes Fluss-Petrol, glimmende Türkisflossen im tiefen Kolk, goldene Lichtkegel auf Kiesbänken und das bedrohliche, tiefe Violett der Flussufer in der Nacht.
4. **Resonanz mit den Grundwerten von Shadowspore**: 
   - *„Licht ist Land – und Ruhe ist Kraft“*: Nach gefahrvollen Erkundungen der Leere und feuchtkalten Tiefen der Mine bietet das Flussufer einen Ort der Regeneration, der Naturbeobachtung und des kooperativen Beisammenseins.

---

## 2. Die Fangmechanik (Das „Wie“)

Das Angeln gliedert sich in vier organische Phasen: **Vorbereiten**, **Driften**, **Bisslesen** und **Drillen im Strom**.

```
[ Uferstand & Köderwahl ] 
          │
          ▼
[ Wurf in die Strömung ] ──► [ Strömungsdrift & Wasserringe ] 
                                          │
                                 (Fisch schöpft Verdacht / Neugier)
                                          │
                                          ▼
                               [ Der Schluck / Biss ]
                                          │
                                          ▼
                             [ Taktiler Drill: "Spannung & Fluss" ]
                                          │
                                          ▼
                               [ Landung & Kesselzutat ]
```

### 2.1 Vorbereitung: Standplatz, Rute & Naturköder
- **Uferposition**: Der Spieler tritt an ein Gewässer. Der Code prüft über `WorldRivers.field_at(pos)`:
  - `field.x > 0.0 and field.x <= 16.0`: Festes Ufer, trockene Füße.
  - `field.x <= 0.0 and field.x >= -6.0`: Seichtes Watwasser (Furt oder Sandbank).
- **Die Rute**: Als Werkzeug in der Schnellleiste (`hotbar: true`, Werkzeugklasse `fishing_rod`).
  - *Eschenrute (Basis)*: Flexibel, verzeiht Schnurfehler, geeignet für kleine und mittlere Fische.
  - *Dornenbiege-Rute (Werkstatt-Ausbau)*: Verstärkt mit Leerenfasern und Knochenspitzen, vermag schwere Tiefenfische aus der Strömung zu heben.
- **Köder aus der lebendigen Natur**:
  Es gibt keine generischen „Köder-Dosen“ beim Händler. Köder werden in der Welt gesammelt und erzählen von ihrer Herkunft:
  - **Wasserläufer / Libellenflügel**: Schwimmt auf, erzeugt winzige Oberflächenimpulse. Beliebt bei sprungfreudigen Raubfischen (*Mondforelle*).
  - **Dämmerbeere / Glimmerbeere**: Sinkt langsam taumelnd ab, verströmt süßen Schimmer. Zieht Schwarmfische (*Silberströmer*) an.
  - **Bachminzen-Blatt / Goldmummel-Knospe**: Lockt pflanzenfressende Ruhigwasserfische (*Goldbauch-Karpfen*).
  - **Glimmkappen-Strunk / Schattenlarve**: Sinkt zügig auf den Grund (`field.y > 0.6`), unwiderstehlich für Bodenbewohner (*Kupferkies-Gründling*, *Schleierdorn*).
- **Anvisieren**: Mit Tastatur/Maus zeigt der Cursor aufs Wasser; am Gamepad steuert der rechte Stick eine sanft pulsierende Zielmarkierung (türkise Pixel-Ellipse, 12×6 px). Nur Positionen mit `field.x < 0.0` (echtes Wasser) sind gültig.

### 2.2 Auswerfen & Posen-Treibphase (Strömungsdrift)
- **Der Wurf**: Nach Loslassen der Aktionstaste holt die Spielfigur aus. Die Sehne schneidet die Luft mit leisem Sirren; die handgeschnitzte Rindenpose landet mit einem dumpfen, hohlen *Plop* im Wasser.
- **Wellen & Physik**:
  - Beim Eintauchen sendet die Pose sofort einen Wellenimpuls über `WaterRipples.add(pos, 0.45)`.
  - Die Pose verharrt nicht an Ort und Stelle! Sie wird vom lokalen Strömungsfeld `WorldRivers.flow_at(pos)` sanft mitgetrieben.
  - In reißender Strömung driftet die Pose schnell flussabwärts; in Stillwasserbuchten oder hinter schützenden Flussfelsen (`river_cover`) dreht sie sich träge im Strömungsschatten.
- **Aktive Posenführung**:
  - **Schnur geben** (`InputManager` / Aktionstaste halten): Die Sehne lockert sich, die Pose darf ungehindert weit mit der natürlichen Flussdrift treiben (ideal, um tiefe Gumpen unter Felsvorsprüngen zu erreichen).
  - **Leichtes Zupfen** (Antippen der Taste): Die Pose zuckt 2–3 Pixel gegen den Strom und erzeugt feine Wasserringe. Dies erregt die Aufmerksamkeit träger Raubfische, verscheucht aber übervorsichtige Schwarmfische, wenn es zu hektisch geschieht.

### 2.3 Das Lesen der Wasserzeichen & der Biss
Bevor ein Fisch anbeißt, kündigt er sich sinnfällig in der Spielwelt an:
1. **Der Schatten nähert sich**: Unter der Wasseroberfläche (über den Shader mit `Color(0.64, 0.85, 0.80, alpha)` moduliert) löst sich eine schemenhafte Fischsilhouette aus dem Federkraut oder Felsenschatten und gleitet zur Pose.
2. **Die Vor-Ringe**: Die Pose wippt leicht. Zwei zarte konzentrische Wasserringe breiten sich aus. Im Gamepad ist ein minimales, trockenes Ticken zu spüren; über die Soundkulisse ertönt ein leises *Tipp-Tipp*.
3. **Der Schluck (Der Biss)**:
   - Der Fisch nimmt den Köder. Die Pose taucht schlagartig ab!
   - Ein kräftiger weißer Schaumring bricht auf (`WaterRipples.add(pos, 1.1)`), gefolgt von einem satten, glucksenden Wassergeräusch.
   - Jetzt muss der Anhieb gesetzt werden (Aktionstaste drücken innerhalb eines großzügigen, aber klaren Zeitfensters von ca. 0.8 bis 1.4 Sekunden, je nach Fischart). Ein panischer Sofort-Klick reißt den Köder aus dem Maul; Zögern lässt den Fisch entwischen.

---

### 2.4 Der Drill: „Spannung & Fluss“ (Kein Stardew-Balken!)

#### Warum kein Standard-Balken-Minispiel?
Ein separater Balken am Bildschirmrand reißt den Spieler aus der visuellen Poesie der 640×360-Flusslandschaft. Stattdessen findet der Drill direkt **auf der Wasseroberfläche** statt:

```
               [RUTENSPITZE]
                     \
                      \  (gespannte Sehne: Bézier-Kurve)
                       \
                        ▼
                 [WASSERWIRBEL] ──► (Fisch flieht stromabwärts)
```

#### Das Prinzip: Taktiles Federn und rhythmisches Einholen
Der Fisch flieht als eigenständige physikalische Kraft im Fluss. Er nutzt die Strömung (`WorldRivers.flow_at()`) und sucht aktiv Schutz in nahegelegenen Wasserpflanzen (Federkraut) oder hinter Felsen.

Der Spieler steuert den Drill über **Richtungswinkel** und **Einholrhythmus**:

1. **Die Fluchtphase (Der Fisch schlägt / flieht)**:
   - Der Fisch schlägt mit der Flosse, schießt stromabwärts oder zur Seite. Die Sehne surrt grell auf.
   - **Reaktion**: Der Spieler darf **nicht kurbeln**, sondern muss die Rute dem Zug entgegenhalten bzw. sanft mitführen (Gamepad-Stick oder Richtungstasten dem Zug leicht nachgeben / federn).
   - *Visuelles Feedback*: Die Sehne spannt sich zu einer fast geraden Linie, glüht weißlich-violett auf, und winzige Wassertropfen sprühen von der Rutenspitze.
   - *Fehler*: Wer krampfhaft gegenreißt, überdehnt die Schnur (steigendes Knacken bis zum Schnurbruch).
2. **Die Ermüdungsphase (Das Kehrwasser / Der Trudel)**:
   - Nach einem Fluchtstoß gerät der Fisch kurz aus dem Gleichgewicht oder wendet quer zur Strömung.
   - **Reaktion**: Die Sehne lockert sich und fällt in eine sanfte, petrol-türkis schimmernde Parabel. **Jetzt ist das Einholfenster!**
   - Der Spieler holt in ruhigen, rhythmischen Zügen ein (Aktionstaste getaktet drücken oder halten). Die Heldin dreht ruhig an der Kurbel, der Fisch wird Meter um Meter herangeführt.
3. **Fluss-Taktik (Hindernisse meiden)**:
   - Schwimmt der Fisch auf ein Federkraut-Feld oder einen Felsen zu, muss der Spieler durch seitliches Neigen der Rute (Bewegungsvektor quer zur Zugrichtung) den Fisch ins freie Fahrwasser umlenken.

#### Die Landung
Erreicht der Fisch das seichte Ufer (`distance < 18 px`), stemmt sich die Heldin kurz ins Ufergras, die Rutenspitze federt hoch, und der Fisch bricht glitzernd durch den Wasserspiegel empor. Ein kurzer, befriedigender Fang-Jingle ertönt, der Fisch rotiert kurz in der Luft und wird gefangen.

---

### 2.5 Multiplayer & Host-Autorität

Shadowspore setzt auf strikte Server-Autorität (`multiplayer.is_server()`). Das Angelsystem integriert sich nahtlos in diese Architektur:

| Element | Host (Server) | Client (Peer) |
|---|---|---|
| **Fisch-Ökologie** | Spawnt Fische in `RiverFauna`, berechnet Wanderung und Hunger. | Rendert Fischschatten anhand der replizierten Positionen. |
| **Wurf & Drift** | Berechnet Trajektorie der Pose, simuliert Strömungsdrift entlang `flow_at()`. | Sendet Wurfziel (`_cast_rod.rpc_id(1, target_pos, bait_id)`), interpoliert Pose lokal. |
| **Biss-Entscheidung** | Prüft Nähe Fisch-Köder, Köderpräferenz, Tageszeit; löst Biss-Event aus. | Empfängt `@rpc("call_local") func _on_bite()` und startet haptisches Feedback. |
| **Drill-Physik** | Simuliert Fischflucht-Vektor, Schnurspannung und Abrieb an Hindernissen. | Sendet Spielerinput (`_reel_input(pull_vec, reeling)`); empfängt Spannungszustand. |
| **Beutevergabe** | Validiert Fangerfolg, generiert Fisch-Item mit Qualitätsattributen, legt es ins Inventar. | Zeigt Landungsanimation und Beute-Toast im HUD. |

**Kooperatives Erlebnis**:
Andere Spieler am Ufer sehen den gesamten Vorgang in voller grafischer Pracht: Sie sehen die geschwungene Sehne, die aufspritzenden Wasserringe des kämpfenden Fisches und können sogar mit einer Fackel Licht spenden oder herannahende Schattenpirscher abwehren, während der Gefährte drillt.

---

## 3. Eingliederung in das Ökosystem

Das Angelsystem dockt direkt an die vorhandene Flussarchitektur (`WorldRivers`, `RiverFauna`, `RiverAnimal`) an:

### 3.1 Interaktion mit der bestehenden Fauna (`river_animals.json`)
- **Fischschwärme (`shoal`) & Einzelfische (`brook`)**:
  - Sie sind keine Attrappen! Die in `RiverFauna` lebenden Instanzen von `shoal` und `brook` reagieren aktiv auf den Köder. Befindet sich die Pose innerhalb des Wahrnehmungsradius eines Schwarmes, löst dies Neugier aus (`desired = bobber.position`).
- **Wasservögel als Gewässeranzeiger**:
  - **Der Reiher (`heron`)**: Reiher stehen nur im Flachwasser mit reichem Kleinfischvorkommen (`heron.STRIKE`). Wo ein Reiher steht, lohnt sich der Wurf – aber man muss Abstand halten!
  - **Der Eisvogel (`kingfisher`)**: Wenn der Eisvogel von seinem Schilfhalm ins Wasser stößt (`kingfisher.PLUNGE`), markiert er exakt eine Stelle, an der gerade Fische an der Oberfläche stehen.
  - **Die Entenfamilie (`duck`)**: Enten beim Gründeln (`duck.DABBLE`) wühlen Bodensedimente und Insektenlarven auf. Für 20–30 Sekunden nach dem Gründeln herrscht an dieser Stelle erhöhte Beißfreude für Grundfische.
- **Scheuch-Mechanik (`RiverFauna.scare_fish`)**:
  - Ein ungeschickter, zu harter Wurf oder lautes Hineintrampeln ins Wasser ruft `RiverFauna.scare_fish(pos, 45.0)` auf.
  - Fische stieben panisch auseinander (`Mode.FLEE`) und suchen Deckung (`cover_target`).
  - **Schleichen zahlt sich aus**: Schleicht der Spieler (`player.stealth.sneaking`), schrumpft sein Furchtradius auf 55% (analog zu `river_animal.gd:92`).

### 3.2 Einfluss von Umweltfaktoren

```
                   TIEFE (field.y)
          0.0 (Seicht) ──────────► 1.0 (Tiefer Kolk)
          ┌──────────────────────┬──────────────────────┐
 TAG      │ Silberströmer        │ Mondforelle          │
          │ Bachkrebse           │ Goldbauch-Karpfen    │
          ├──────────────────────┼──────────────────────┤
 NACHT    │ Schilfkrabben        │ Schleierdorn-Aal     │
 (Gefahr) │ Leuchtelritzen       │ Tiefen-Schattenschlund│
          └──────────────────────┴──────────────────────┘
```

1. **Wassertiefe (`field.y`) & Strömungsgeschwindigkeit**:
   - **Kiesfurt & Flachsaum (`field.y < 0.35`)**: Schnelle, quirlige Schwarmfische. Klares Wasser, wenig Hänger-Risiko.
   - **Hauptstrom (`field.y 0.35..0.7`)**: Kräftige Strömung, Heimat ausdauernder Salmoniden. Verlangt feinfühlige Schnurkontrolle gegen den Abdrift.
   - **Tiefe Kolke & Seenbecken (`field.y > 0.7`, `lake_at == true`)**: Dunkle, träge Wasserkörper. Hier lauern schwere Bodenfische, die kräftige Ruten fordern.
2. **Tageszeit & Nacht-Dramaturgie**:
   - **Tag**: Friedliche Flussidylle, zwitschernde Vögel, klares Wasser. Die meisten Speisefische beißen verlässlich.
   - **Dämmerung**: Die goldene Stunde. Raubfische verlassen ihre Verstecke im Federkraut; die Beißrate steigt spürbar.
   - **Nacht (Die Voidbloom-Gefahr)**: 
     Nachts verändert sich die Welt grundlegend (`TimeManager.is_night()`):
     - Aus den Tiefen steigen geheimnisvolle Leuchtfische empor, deren Flossen im dunklen Wasser türkis schimmern.
     - **Aber**: Das Angeln bei Nacht birgt echte Lebensgefahr. Die Heldin steht still am Wasser, während Schattenkreaturen aus Rissen kriechen. Eine aufgestellte Laterne spendet Ruhe; ideal ist das Nachtangeln zu zweit: Ein Spieler angelt, der andere hält mit Schwert und Fackel die Wache.

---

## 4. Beute, Fischarten & Koch-Synergie

### 4.1 Die 5 Leit-Fischarten

| Fischart | Lebensraum & Tiefe | Bevorzugter Köder | Verhalten beim Drill | Kulinarische Eigenschaft |
|---|---|---|---|---|
| **Silberströmer** *(Shoal Minnow)* | Helle Kiesbänke, Seichtwasser (`field.y < 0.35`) | Dämmerbeere, Brotflocke | Zappelig, kurze schnelle Fluchten, gibt schnell auf. | **Zart & Frisch**: Bringt feine Eleganz in leichte Kräuterbrühen. |
| **Kupferkies-Gründling** *(Gravel Loach)* | Felsunterstände im schnellen Strom (`river_cover`) | Schattenlarve, Glimmkappen-Strunk | Stemmt sich stur auf den Grund, nutzt Steine als Deckung. | **Erdig & Mineralisch**: Bildet eine kräftige Basis für sämige Eintöpfe. |
| **Mondforelle** *(Moonfin Trout)* | Gumpen unter Wasserfällen & Strömungskanten | Wasserläufer, Libelle, Schimmerfliege | Kraftvoll, springt aus dem Wasser, schlägt mit der Strömung. | **Samtig & Nussig**: Hoher Fettgehalt, schmilzt auf der Zunge beim Rasten. |
| **Goldbauch-Karpfen** *(Sunbelly Carp)* | Ruhige Seebuchten unter Linsenteppichen | Goldmummel-Knospe, Bachminze | Träges Schwergewicht, zieht stur in Wasserpflanzen. | **Süßlich & Bindend**: Dichtes Fleisch, verleiht Saucen seidige Textur. |
| **Schleierdorn-Aal** *(Veil Barb)* | Dunkelste Tiefen (`field.y > 0.8`), **nur bei Nacht** | Glimmkappe, Leerenmade | Zieht schlangenartig in Spalten, reißt plötzlich an der Rute. | **Umami & Wärmend**: Mystisch-intensiv, verleiht langanhaltende Vitalität. |

---

### 4.2 Direkte Synergie mit „Lies den Kessel“ (`docs/cooking.md`)

In Shadowspore besitzt das Kochen ein dreistufiges System mit sensorischen Nuancen (Ansehen, Riechen, Schmecken) und sechs Geschmackscharakteren (*frisch, samtig, fruchtig, leicht, wärmend, rauchig/herb*).

Fische fügen sich perfekt in diese Dreiteilung ein:

```
                  KOCHSTUFE 1: DIE BASIS
   [Sanft anschwitzen]   [Im Rauch ziehen]   [Im Quellsud pochieren]
            │                     │                     │
            ▼                     ▼                     ▼
        (samtig)              (kräftig)              (frisch)
                                  │
                                  ▼
             KOCHSTUFE 2: DER GESCHICKLICHKEITSMOMENT
       (Timing-Marker: Garpunkt des Fisches treffen)
     * Perfekt: Glasig, butterweich, behält alle Essenzen
     * Zu früh: Fleisch noch fest, gibt wenig Aroma ab
     * Zu spät: Fleisch zerfällt, trübt die Brühe herber ein
                                  │
                                  ▼
             KOCHSTUFE 3: DER LETZTE HANDGRIFF
   [Bachminze zugeben]   [Vom Feuer ziehen]   [Kräftig reduzieren]
```

#### Beispielrezept: *Mondforellen-Kesselsud*
- **Zutaten**: 1× Mondforelle, 2× Bachminze, 1× Glimmkappe.
- **Sensorische Hinweise beim Kochen**:
  - *Riechen*: „Ein Duft von frischem Flusswasser und kühler Minze steigt empor. Kein Anflug von Moder.“
  - *Sehen*: „Das Filet schimmert perlmuttfarben. Feine Fettaugen glänzen auf der Brühe.“
  - *Probieren*: „Samtig und rein. Die Minze fängt die Reichhaltigkeit der Forelle perfekt auf.“
- **Wirkung im Spiel**:
  - Ein vollendeter, *samtig-frischer* Mondforellen-Sud spendet den Buff **„Flussläufer-Atem“**: 15 Minuten lang verbraucht das Watten im Wasser keine Ausdauer, und die Bewegungsgeschwindigkeit im seichten Wasser ist um 20% erhöht.

---

## 5. Mehrwert & Spielerlebnis

Warum bereichert dieses Angelsystem Shadowspore nachhaltig?

1. **Erdung im Spiel-Pacing (Atmosphärische Balance)**:
   Shadowspore bietet nervenaufreibende Scharmützel gegen die Brut der Leere, klaustrophobische Abenteuer in den Tiefen der Mine und rasante Bosskämpfe. Ein Spiel braucht jedoch Täler der Ruhe, um Höhen der Spannung wirken zu lassen. *„Lies das Wasser“* gibt dem Spieler einen triftigen, lohnenden Grund, am Flussufer innezuhalten, den Geräuschen der Natur zu lauschen und den Flusslauf zu studieren.
2. **Die Natur als echtes System, nicht als Dekoration**:
   Bäume, Sträucher, Wasserpflanzen und Tiere sind nicht bloß Kulisse. Wenn der Spieler versteht, dass die Libelle der beste Köder für die Forelle ist, dass die Ente die Fische füttert und dass der Schatten des Reihers Gefahr bedeutet, wird die Spielwelt zu einem konsistenten, lebendigen Kosmos.
3. **Gemeinschaftsgefühl im Co-op**:
   Gemeinsam auf einem Holzsteg am See sitzen, während die Sonne langsam hinter den Wipfeln versinkt. Ein Spieler bereitet am Kessel das Feuer vor, während der andere die Abendforelle drillt. Es entstehen organische, unvergessliche Spielmomente.
4. **Verbindung aller Gameplay-Säulen**:
   - **Erkundung**: Finde abgelegene Bergquellen und tiefe Waldseen.
   - **Handwerk / Siedlung**: Gustav hilft beim Schnitzen edler Ruten und Posen.
   - **Kochen**: Verwandle den Fang in meisterhafte Speisen für schwere Dungeons.

---

## 6. Technische Umsetzung in Godot 4.7

### 6.1 Datenstrukturen (`res://data/fishing.json`)

```json
{
  "rods": {
    "rod_basic": {
      "name": "Eschenrute",
      "line_strength": 35.0,
      "flex": 1.2,
      "max_cast_dist": 96.0,
      "durability": 50
    },
    "rod_hardened": {
      "name": "Dornenbiege-Rute",
      "line_strength": 65.0,
      "flex": 0.85,
      "max_cast_dist": 140.0,
      "durability": 120
    }
  },
  "baits": {
    "dusk_berry": {
      "name": "Dämmerbeere",
      "sink_rate": 0.4,
      "scent_radius": 48.0,
      "attracts": ["shoal_minnow", "sunbelly_carp"]
    },
    "dragonfly": {
      "name": "Libelle",
      "sink_rate": 0.0,
      "scent_radius": 72.0,
      "attracts": ["moonfin_trout"]
    },
    "shadow_grub": {
      "name": "Schattenlarve",
      "sink_rate": 0.9,
      "scent_radius": 60.0,
      "attracts": ["gravel_loach", "veil_barb"]
    }
  },
  "fish": {
    "moonfin_trout": {
      "name": "Mondforelle",
      "item_id": "fish_moonfin_trout",
      "min_depth": 0.4,
      "max_depth": 0.8,
      "stamina": 14.0,
      "pull_force": 42.0,
      "burst_interval": [2.5, 5.0],
      "jump_chance": 0.35,
      "active_time": "twilight_and_day"
    },
    "veil_barb": {
      "name": "Schleierdorn-Aal",
      "item_id": "fish_veil_barb",
      "min_depth": 0.75,
      "max_depth": 1.0,
      "stamina": 22.0,
      "pull_force": 58.0,
      "burst_interval": [1.8, 4.0],
      "active_time": "night_only"
    }
  }
}
```

### 6.2 Node-Architektur & Szenenhierarchie

```
FishingController (Node2D, am Player angehängt)
 ├── Bobber (Node2D, instanziiert im Weltraum)
 │    ├── Sprite2D (Posen-Sprite, 16×16 px)
 │    ├── WaterRipples (Wellen-Emitter)
 │    └── Area2D (Wahrnehmungsfeld für Fische)
 ├── FishingLine (Line2D, dynamischer Bézier-Renderer)
 └── AudioStreamPlayer2D (Surren der Rolle, Eintauch-Plop, Drill-Spannung)
```

- **`FishingController.gd`**:
  - Verwaltet den Zustandsautomaten: `IDLE` → `AIMING` → `CASTING` → `DRIFTING` → `NIBBLE` → `HOOKED` → `FIGHT` → `LANDED`.
  - Liest alle Steuereingaben ausschließlich über `InputManager`.
  - Bindet an `WorldRivers`: Fragt `field_at(bobber.global_position)` und `flow_at(bobber.global_position)` ab.
- **`FishingLine.gd`**:
  - Nutzt `Line2D` mit 8–12 Stützpunkten.
  - Berechnet eine physikalisch durchhängende Katenoid- bzw. Bézier-Kurve zwischen Rutenspitze und Pose.
  - Bei hoher Spannung (`tension > 0.8`) wird die Linie schmal (1 px) und erhält im Shader ein vibrierendes, weiß-violettes Schimmern.

### 6.3 Asset- & Shader-Bedarf
1. **Sprites (16-px-Raster, Pixelart)**:
   - `fishing_rod_basic.png` / `fishing_rod_held.png` (Rute in Ruhe und gebogen unter Last).
   - `fishing_bobber.png` (4 Frames: Schwimmend, Zitternd, Untergetaucht, Leer).
   - Fisch-Items für Inventar & Kessel (`fish_minnow.png`, `fish_trout.png`, etc., je 16×16 px).
2. **Shader-Erweiterung**:
   - `fishing_line.gdshader`: Schnurspannungsvibration und Farbinterpolation (Petrolgrün `3cc0c6` bei Entspannung → Violettrot `ff4a63` bei Zerreißgefahr).
3. **Sound-Design**:
   - `rod_cast.wav`: Feines Zischen einer geschwungenen Rute.
   - `bobber_plop.wav`: Weiches, hohles Eintauchen in Wasser.
   - `line_reel.wav`: Taktiles Klicken einer geschnitzten Holzspule.
   - `fish_splash.wav`: Aufbäumendes Platschen im Wasser beim Drill.

---

## 7. Fazit

*„Lies das Wasser“* ist kein Fremdkörper in Shadowspore, sondern die konsequente Vollendung unserer bestehenden Natur- und Flusssysteme. Es belohnt Geduld, Beobachtungsgabe und Rhythmusgefühl, bindet die reiche Tierwelt organisch ein und beliefert das Kochsystem *„Lies den Kessel“* mit edlen, differenzierten Zutaten. 

Damit erhält Shadowspore ein hochgradig atmosphärisches, mechanisch tiefes Feature, das sowohl Solo als auch im Co-op das Markenzeichen des Spiels unterstreicht: **Eine Welt, die lebt, atmet und aufmerksam erforscht werden will.**
