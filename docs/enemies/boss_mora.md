# Gegner-Dossier: Boss 2 – Morwenna, die Spiegelhexe (Die Zerrissene)

> *„Valdric... sieh dir ihr Siegel an der Klinge an. Das ist kein Monster des Waldes. Das ist Morwenna... die Großhexe, von der die Chroniken sprachen!“*  
> *„Götter der Zinne. Sie starb also nicht am Großen Riss... Sie hat versucht, sich selbst zu binden. Doch die Leere nagte schon an ihrem Verstand. Sie ist gefangen zwischen Leben und Nichts – und dieser Baum hält ihren zerfallenden Leib zusammen.“*  
> — **Ellie und Valdric**, an der Schwelle zum Schieferkessel

---

### 1. Basis & Physische Präsenz
* **Name & HUD-Titel:** `MORWENNA, DIE SPIEGELHEXE` (HUD-Untertitel: `Die Zerrissene` / `Schänderin des Rabenbaums`)
* **Interner Bezeichner (ID):** `boss_mirror_witch` / `boss_morwenna`
* **Klassifizierung:** Gefallene Großhexe / Instabiles Void-Phänomen (Boss 2)
* **Arena & Habitat:** 
  * Der *Schieferkessel am Rabenbaum* im Hexenwald (Tile `879, 914`).
  * Eine tiefe Schiefermulde mit dem uralten, leidenden Rabenbaum im Zentrum.
* **Erscheinungsbild, Silhouette & Anatomie:**
  * **Größe & Haltung:** Ca. 48 px hoch, 32 px breit. Gebeugte, drahtige Frauen-Silhouette in zerschlissener, einst edler Magierseide, die in Moos, Baumharz und schwarze Void-Tentakel übergeht.
  * **Kopf & Maske:** Spitz zulaufender Hexenhut mit vertrockneten Zweigen. Ihr Gesicht ist hinter einer schmutzigen, rissigen Spiegelscherbe verborgen, in der sich abwechselnd Ellies Antlitz und die Leere brechen. Dahinter brennen zwei violette Fluchfeuer.
  * **Waffen:** Zwei verrostete, uralte Zeremonien-Sicheln aus Fluchsilber.
  * **Bewegungsstil:** Bodenständig, rasend agil, huschend wie ein gehetztes Raubtier.

---

### 2. Ursprung & Die Tragödie des gescheiterten Wandels
* **Die Großhexe:** Morwenna war einst die mächtigste Meisterin des Alten Zirkels. Als der Große Riss aufbrach, kämpfte sie an vorderster Front, wurde jedoch tödlich von der Leere infiziert.
* **Das missglückte Notfall-Ritual:** Um ihr Leben zu retten, schleppte sie sich zum Großen Rabenbaum und versuchte, ihre Seele in das unsterbliche Herzholz zu binden. Doch der Void zersetzte ihren Zauber mitten im Vollzug: **Das Ritual stoppte mitten in der Transformation.**
* **Der Transmutations-Limbus:** Sie existiert seither in einem permanenten, instabilen Zwischenzustand zwischen Materie und Nichts.
* **Warum sie den Baum aussaugt:** Sie saugt den Rabenbaum nicht aus Bosheit aus, sondern weil sie buchstäblich zerfällt, wenn sie nicht ununterbrochen die pure Lebenskraft des Baumes in ihren zerrissenen Körper pumpt. Der Baum ist ihre Beatmungsmaschine – und die Raben sehen hilflos zu, wie ihr Heiligtum stirbt.

---

### 3. Psychologischer Kern & Glitch-Verhalten
* **Grundantrieb (Want):**
  * **Verzweifeltes Überleben um jeden Preis.** Jeder Abbruch der Energieverbindung bedeutet für sie den sofortigen Sturz ins Nichts.
* **Tiefstes Bedürfnis (Need):**
  * **Erlösung vom ewigen Zerrissenwerden.** Ein Teil ihres ursprünglichen Geistes fleht darum, endlich ruhen zu dürfen.
* **Glitch-Verhalten als Gameplay-Kern:**
  * **Micro-Stutter:** Nach bestimmten Aktionen friert ihr Sprite für 2–3 Frames ein (Frame-Hold mit Knistern).
  * **Spasmen:** Ihr Körper zuckt unwillkürlich mitten in der Bewegung zur Seite – der Kampf ihres Geistes gegen die Leere.
  * **Zweistimmigkeit:** Morwennas Stimme ist gedoppelt – eine erhabene Hexe überlagert von einem kratzenden Void-Echo.
  * **Die Feindschaft der Raben:** Die Raben hassen und fürchten Morwenna. Wenn sie Klone ruft, kreischen die Vögel über der **echten** Hexe.

---

### 4. Das 5-Schritte-Konzept

#### Schritt 1: Arena-Design, Rabenbaum-Veredelung & Versiegelung
* **Rabenbaum-Upgrade (`CrowTree`):**
  * `trunk.png`: Knorriges Totholz mit pulsierenden violett-grünen Ritualadern (`#a8ff6a`), wo Morwenna die Wurzeln anzapft.
  * `crown.png`: Dichte Astkronen mit unruhigem Shader-Wanken.
  * `charms.png`: Verfluchte Spiegelsplitter und magische Fesseln des Rituals.
  * 16 Perch-Punkte für die ängstlich kauernden Raben.
* **Arena-Clearing:**
  * 14-Tile-Radius um den Baum leeren (keine störenden Büsche/Felsen) für flüssiges Ausweichen.
  * Deko: Spinnweben an den Wurzeln, Galleblasen, verstreute Federn gequälter Vögel.
* **Vorkampf:**
  * 3 Schattenspinnen (Auswüchse ihrer Void-Fäulnis) klammern das Wurzelwerk. Nach ihrem Tod bricht Morwennas Halt und der Bosskampf beginnt.
* **Versiegelung & Klettersperre:**
  * Tore schließen durch Dornen und instabilen Void-Nebel.
  * `WallClimb` an den Klippen wird durch einen stoßartigen Schattenabwind abgewiesen.

#### Schritt 2: Boss-Auftritt (Sturz aus der Baumkrone)
1. Die 3 Spinnen sterben.
2. Der Boden vibriert. Die Raben in der Krone kreischen im Chor.
3. Morwennas zweistimmiger Schrei: *„Nein! Reißt das Band nicht ab! Ich... löse mich auf...!“*
4. Morwenna stürzt kopfüber aus der dichten Krone herab, schlägt vornüber im Lehm auf. Ihr Körper glitched in drei Geisterbildern, bevor sie sich ruckartig aufrichtet und die Sicheln wetzt.
5. Bossbalken füllt sich: `MORWENNA, DIE SPIEGELHEXE`.

#### Schritt 3: Raben-Dynamik & Glitch-Klone
* **Die Raben als Helfer:**
  * Raben kreisen über der Arena und werden von Phase zu Phase wilder.
  * **Schlüsselsignal:** Wenn Morwenna Klone ruft, kreischen die Raben in der Luft genau über der **echten** Morwenna.
* **Glitch-Klone:**
  * Klone sind flüchtige Raum-Fragmente ihrer instabilen Existenz mit Scanline-Shader (`glitch_phantom.gdshader`).
  * Alle 1,5–2,2 s verschiebt sich ein horizontaler Streifen (Slice-Offset); Augen zucken hexengrün (`#a8ff6a`), während Morwenna violett brennt.
  * Klone hinterlassen **keinen Bodenschatten** (`ShadowPatch`).
  * Treffer auf Klone: Verpuffen widerstandslos in faulem Nebel.
  * **Glitch-Swap:** Morwenna kann blitzschnell den Platz mit einem Klon tauschen.

#### Schritt 4: Der Detail-Movepool (Phasen 1, 2 & 3)

##### Phase 1 (100 % – 66 % HP): Der Kampf ums Überleben
* **1.1 Harzschnitt-Kombo (`act_resin_slash`):** 3-teilige Kombo mit Micro-Stutter (Frame-Hold) vor dem finalen Scherenschnitt.
* **1.2 Zick-Zack-Huschen (`act_shadow_prowl`):** Flinker 3-Stufen-Bodensprint um Ellie herum in ihren toten Winkel.
* **1.3 Wurzelspeer (`act_root_lance`):** Rammt Sichel in den Boden; 3 spitze Holzwurzeln brechen zeitversetzt unter Ellies Füßen hervor.
* **1.4 Fluchsaft-Fächer (`act_sap_spray`):** Akrobatischer Rückwärtssprung (3 Tiles); schleudert 5 faulige, verlangsamende Harztropfen im Fächer.
* **1.5 Schatten-Finte (`act_feint_dash`):** Vorstoß; löst sich 5 px vor Ellie in Rauch auf und materialisiert 1 Tile hinter ihr für einen Fersenschnitt.

##### Phasenwechsel 1 ➔ 2 (bei 66 % HP)
* Morwenna packt sich an die Maske: *„Die Risse... sie schließen sich nicht mehr...!“*
* Ein gewaltiger Riss durchzieht das Glas. Screen-Card: `DER SPIEGEL ZERBRICHT`.
* Druckwelle schleudert Ellie zurück; der **erste permanente Glitch-Klon** löst sich ab. Die Raben kreisen tiefer und hektischer.

##### Phase 2 (66 % – 33 % HP): Die Abspaltung
* **2.1 Scheren-Zange (`act_pincer_flank`):** Morwenna und Klon sprinten synchron aus 90°-Winkeln aufeinander zu; Schnittpunkt detoniert in Schockwelle.
* **2.2 Spiegelscherben-Projektil (`act_refraction_shards`):** Dreht Maske; 3 Scherben prallen an den Schieferklippen im Winkel ab.
* **2.3 Wurzel-Unterwanderung (`act_burrow_ambush`):** Taucht mit Glitch-Sound in die Wurzeln ab; Erdwulst rast auf Ellie zu, während der Klon sie bindet.
* **2.4 Glitch-Swap (`act_glitch_swap`):** Tauscht bei Gegenangriff mit Störgeräusch den Platz mit dem Klon *(Raben kreischen über der echten!)*.
* **2.5 Fluchspiegel-Käfig (`act_mirror_cage`):** 4 Spiegelsplitter werden im Kreis gerammt; giftige Laserfäden spannen sich für 2,5 s.

##### Phasenwechsel 2 ➔ 3 (bei 33 % HP)
* Morwenna stürzt vor den Stamm: *„Nein... NEIN! Ich werde nicht ins Nichts stürzen! NÄHRE MICH!“*
* Saugt gewaltsam Lebenskraft; Tag schlägt in pechschwarze Nacht um. Baum glüht hexengrün.
* Maske splittert fast ganz ab. Screen-Card: `DIE HEXENSTUNDE`.
* Der **zweite Glitch-Klon** tritt hervor; der Rabenschwarm gerät in blindes Chaos.

##### Phase 3 (33 % – 0 % HP): Die Hexenstunde (Der finale Kollaps)
* **3.1 Phantom-Karussell (`act_phantom_carousel`):** Dreiecksformation rotiert rasant um Ellie; Gestalten stoßen nacheinander nach innen vor.
* **3.2 Lebensraub-Puls (`act_tree_leech`):** Morwenna zapft die Hauptwurzel an; 3 Schockwellenringe laufen über die Arena *(Unterbrechbar durch schweren Treffer!)*.
* **3.3 Wahnsinns-Rasantanz (`act_frenzy_flurry`):** 5-facher Dash-Angriff quer durch den Kessel mit detonierenden Fluchlinien.
* **3.4 Glitch-Split (`act_glitch_split`):** Alle 3 Gestalten lösen sich in Scanlines auf und laden Strahlen auf. Nur der Echte schadet *(Raben kreischen über ihr!)*.
* **3.5 Panikschrei des Schwarms (`act_panicking_swarm`):** Gequälter Schrei treibt Vögel tief durch die Mulde; Federn schränken Sicht ein. Bodenabdrücke beachten!

---

#### Schritt 5: Die Erlösung & Technische Spezifikation
* **Erlösung:** Morwenna bricht zusammen. Für zwei Sekunden klärt ihr Blick auf: *„Die Kälte... sie lässt nach.“* Sie löst sich friedlich in goldenen Staub auf.
* **Befreiung:** Der Baum atmet auf, das Giftgrün weicht warmem Licht, die Raben besetzen friedlich alle 16 Äste.
* **Drop:** `Scherbe der Klarsicht` (+Resistenz gegen Verwirrung, Schein-Gegner im Hexenwald grün markiert, +15 % Ausdauer nach Dash).

---

### 5. Dialoge an der Schwelle

```dialogue
[VOR DEM KAMPF - NACH BESIEGEN DER SPINNEN]
Ellie:   "Die Netze sind zerrissen! Aber Valdric... sieh dir die Vögel an.
          Sie schreien vor Angst! Was sitzt da oben im Geäst?"
Valdric: "Das ist kein gewöhnliches Ungeheuer, Ellie. Sieh die Robe...
          Das ist Morwenna. Die Großhexe des alten Zirkels!
          Sie ist am Riss nicht gestorben... sie steckt im Wandel fest!"
(Krachen in den Ästen - Morwenna stürzt herab, glitched auf dem Boden)
Morwenna:"Nein... rührt das Holz nicht an! Wenn das Band reißt... 
          holt mich die Leere! ICH WILL NICHT VERGEHEN!"

[PHASENWECHSEL 2 - DIE HEXENSTUNDE]
Morwenna:(stimmlich zweigeteilt, ringt mit sich)
         "Lauf weg, kleines Mädchen... ICH KANN SIE NICHT MEHR HALTEN!
          DER BAUM GEHÖRT MIR!"
Valdric: "Ihr Geist zerfällt, Ellie! Halt durch!
          Hör auf die Raben – sie zeigen dir, wo ihr echter Körper steht!"

[NACH DEM SIEG - DIE ERLÖSUNG]
Morwenna:(liegt im Moos, Maske zerbrochen, blickt zu Ellie)
         "Es... tut nicht mehr weh. Die Stimmen schweigen.
          Danke... Kind des Lichts..."
         (Löst sich friedlich in goldenen Staub auf)
Ellie:   "Sie war die ganze Zeit wach da drin, Valdric.
          Sie war gefangen in ihrem eigenen Körper."
Valdric: (neigt ehrfürchtig das Haupt)
         "Ruhe sanft, Morwenna. Dein Wachen ist vorbei.
          Der Baum atmet wieder."
```

---

### 6. Ingame-Verzeichnisse & Dateireferenzen für den Implementierungs-Agenten

#### 6.1 Rabenbaum & Arena-Vorbereitung (Schritt 1)
* **Tree Generator Skript:** [`tools/art_crow_tree.py`](file:///Users/nxye/voidbloom/tools/art_crow_tree.py) (Python-Skript für Texturlagen `trunk`, `crown`, `charms`, `moss`, `glow`, `pad`).
* **Tree Textur-Assets:** [`assets/props/crow_tree/`](file:///Users/nxye/voidbloom/assets/props/crow_tree/) (PNGs und Metadaten `crow_tree.json`).
* **Tree Ingame-Node:** [`src/entities/props/crow_tree.gd`](file:///Users/nxye/voidbloom/src/entities/props/crow_tree.gd) (Node2D-Klasse `CrowTree`, Sway-Shader & `RoofPerch`-Instanzen).
* **Tree Site & Arena Data:** [`data/crow_tree_site.json`](file:///Users/nxye/voidbloom/data/crow_tree_site.json) (Koordinate `[879, 914]`, Radius `12`, Spinnenkoordinaten).
* **World Spawner:** [`src/world/world_level.gd`](file:///Users/nxye/voidbloom/src/world/world_level.gd#L279-L284) (`CrowTree`-Instanziierung & `_clear_around`).
* **Tree Sway Shader:** [`assets/shaders/sway_rows.gdshader`](file:///Users/nxye/voidbloom/assets/shaders/sway_rows.gdshader) (Shader für Ast- und Talismanwanken).
* **Boden- & Pfad-Masken:** [`assets/world/ground/hexenwald_path.png`](file:///Users/nxye/voidbloom/assets/world/ground/hexenwald_path.png) (Pfadmasken im Hexenwald).

#### 6.2 Vorkampf: Die 3 Schattenspinnen
* **Spider Enemy Class:** [`src/entities/enemies/shadow_spider.gd`](file:///Users/nxye/voidbloom/src/entities/enemies/shadow_spider.gd) (Logik, Angriffe, Hitbox).
* **Spider Scene:** [`src/entities/enemies/shadow_spider.tscn`](file:///Users/nxye/voidbloom/src/entities/enemies/shadow_spider.tscn) (Szene der Schattenspinne).
* **Spider Rig:** [`src/entities/enemies/spider_rig.gd`](file:///Users/nxye/voidbloom/src/entities/enemies/spider_rig.gd) (Chitin- und Beinanimationen).
* **Spider Textures:** [`assets/enemies/shadow_spider_body.png`](file:///Users/nxye/voidbloom/assets/enemies/shadow_spider_body.png) (Grafikbasis).

#### 6.3 Boss-Implementierung & Klon-System (Schritt 2, 3 & 4)
* **Boss Controller (Neu):** `src/entities/enemies/witch_boss/mirror_witch.gd` (Hauptknoten, `CharacterBody2D`, Micro-Stutter).
* **Boss Fight State Machine (Neu):** `src/entities/enemies/witch_boss/mirror_witch_fight.gd` (Timeline-Queue, nachempfunden nach `MornathFight`).
* **Glitch-Klon Node (Neu):** `src/entities/enemies/witch_boss/witch_clone.gd` (Autonomer Dummy ohne HP, spiegelt Morwennas Angriffe).
* **Glitch Shader (Neu):** `assets/shaders/glitch_phantom.gdshader` (Scanlines, Slice-Offsets, Frame-Holds, Hexengrün-Flicker `#a8ff6a`).
* **Boss HUD Health Bar:** [`src/ui/boss_bar.gd`](file:///Users/nxye/voidbloom/src/ui/boss_bar.gd) (`call_group("boss_bar", "track", "NAME", health)`).
* **Phase Transition Screen:** [`src/ui/boss_phase_screen.gd`](file:///Users/nxye/voidbloom/src/ui/boss_phase_screen.gd) (`BossPhaseScreen.play`, z. B. `DER SPIEGEL ZERBRICHT`).
* **Boss Intro Shader:** [`assets/shaders/boss_intro.gdshader`](file:///Users/nxye/voidbloom/assets/shaders/boss_intro.gdshader) (Schattenrauch-Balken).
* **Boss Aura FX:** [`assets/shaders/boss_aura.gdshader`](file:///Users/nxye/voidbloom/assets/shaders/boss_aura.gdshader) (Void-Aura).

#### 6.4 Rabenschwarm-Ökologie & Arena-Verhalten
* **Corvid Population:** [`src/world/corvid_population.gd`](file:///Users/nxye/voidbloom/src/world/corvid_population.gd) (Schwärme, Perches, Flugrichtungen).
* **Corvid Scene:** [`src/world/corvid_population.tscn`](file:///Users/nxye/voidbloom/src/world/corvid_population.tscn) (Vogelszene).
* **Corvid Wildlife Audio:** [`assets/audio/wildlife/raven_0.wav`](file:///Users/nxye/voidbloom/assets/audio/wildlife/raven_0.wav) & [`raven_1.wav`](file:///Users/nxye/voidbloom/assets/audio/wildlife/raven_1.wav) (Krächz- & Alarmrufe).
* **Corvid Audio Generator:** [`tools/audio_corvid.py`](file:///Users/nxye/voidbloom/tools/audio_corvid.py) (Audiosynthese).

#### 6.5 Texturabgleich & Stil-Referenzen (Farben & Proportionen)
* **Hexen-NPC Referenz:** [`tools/art_witch.py`](file:///Users/nxye/voidbloom/tools/art_witch.py) (Proportionen, Farbreihen `DRESS`, `HAT`, `HEXG`).
* **Hexen-Rig Daten:** [`data/witch_rig.json`](file:///Users/nxye/voidbloom/data/witch_rig.json) (Frame `[76, 96]`, Feet `[38, 80]`).
* **Baum-Stil Referenzen:** [`assets/props/hag_tree.png`](file:///Users/nxye/voidbloom/assets/props/hag_tree.png) & [`assets/props/bone_tree.png`](file:///Users/nxye/voidbloom/assets/props/bone_tree.png) (Hexenwald-Baumtexturen).
* **Hexenwald Farbpalette:** [`assets/shaders/ground_tone.gdshader`](file:///Users/nxye/voidbloom/assets/shaders/ground_tone.gdshader) (Hex-Rampe: `#0d0f1a`, `#131e26`, `#1b2c2d`, `#273d38`, `#38503f`, `#506848`).
* **Hexengrün Leuchtfarbe:** `#a8ff6a` (Standard-Glow für Halluzinationen und Zauber im Hexenwald).
* **Biome Konfiguration:** [`data/biomes.json`](file:///Users/nxye/voidbloom/data/biomes.json) (Eintrag `witch_forest`, Kartenfarbe `#4d5f72`).

#### 6.6 Klettersperre, Status-Effekte & Belohnungen (Schritt 5)
* **Player Wall Climb:** [`src/components/wall_climb.gd`](file:///Users/nxye/voidbloom/src/components/wall_climb.gd) (Kletter-Komponente).
* **Wall Climb Data:** [`data/wall_climb.json`](file:///Users/nxye/voidbloom/data/wall_climb.json) (Reichweiten-Parameter).
* **Status Effects:** [`src/components/status_effects.gd`](file:///Users/nxye/voidbloom/src/components/status_effects.gd) & [`data/status_effects.json`](file:///Users/nxye/voidbloom/data/status_effects.json) (`HALLUZINIERT`-Status).
* **Boss Relic Spawner:** [`src/systems/boss_relics.gd`](file:///Users/nxye/voidbloom/src/systems/boss_relics.gd) (Drop-Verwaltung für Relikte).
* **Enemies Loot Database:** [`data/enemies.json`](file:///Users/nxye/voidbloom/data/enemies.json) (Drop-Eintrag für Boss 2).
* **Talisman Database:** [`data/talismans.json`](file:///Users/nxye/voidbloom/data/talismans.json) (Werte für `Scherbe der Klarsicht`).
* **Blueprint Boss 1 (Mornath):** [`src/entities/enemies/mornath_fight.gd`](file:///Users/nxye/voidbloom/src/entities/enemies/mornath_fight.gd) (Referenz für State Machine, RPC-Sync und Phasenwechsel).
