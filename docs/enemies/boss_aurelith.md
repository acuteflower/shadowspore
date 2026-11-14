# Gegner-Dossier: Wüsten-Boss – Aurelith, Herz des Sonnenquarzes

> *Kein Grollen der Leere. Nur das tiefe Singen verglaster Dünen, das Knistern von siebentausend Jahren aufgestauter Sonnenmagie – und sechs kleine steinerne Wächter, die still um ein halb versunkenes Herz kreisen.*

---

## 1. Basis & Identität

* **Name & HUD-Titel:** `AURELITH, HERZ DES SONNENQUARZES` *(Untertitel: Der Ewige Monolith / Erster Schmelzer)*
* **Interner Bezeichner (ID):** `boss_aurelith`
* **Klassifizierung:** Antikes Astral-Schmelzkonstrukt / Schwebender Quarz-Sandstein-Titan (Optionaler Endgame-Pinnacle-Boss der Sonnenquarz-Öde)
* **Stimm- & Sprachcharakter:** **Komplett stumm & erhaben.** Aurelith spricht keine einzigen Dialogzeilen und besitzt keine Textbox-Stimme. Seine Präsenz wirkt ausschließlich über majestätische Haltung, fließende Kraftbänder, aufglühende Runenmuster sowie tiefe Stein-, Kristall- und singende Resonanzklänge.
* **Schwierigkeits-Einordnung:** **Brutaler Endgame-Pinnacle-Boss (~2500 LP solo vor Koop-Skalierung)** — deutlich härter als Mornath (900 LP) und Morwenna (1300 LP), ausgelegt als härteste optionale Kampfprüfung der Wüste, aber **ohne Story-Sperre von Beginn an frei auffindbar und weckbar**.
* **Waffen- & Zauber-Prinzip:** **Reiner Waffen- & Zauberfokus ohne extra Spitzhacken-Bonus.** Leichte und schwere Waffenangriffe sowie sämtliche Zauberstab-Schulen brechen kleine Wächter, Schilde und das offene Kristallherz gleichwertig und schleudern zurückgeworfene Resonanz-Kerne direkt in Aurelith zurück.

---

## 2. Ursprung & Mythologie („Warum liegt er im fernen Sand?“)

* **Die Ära der Himmelsbaumeister:** Lange bevor Schattenwesen das Land bedrohten, formten die Erbauer der *Zenitwarte* (Region 34) die Nordwüste mit gewaltigen Schmelzkonstrukten. **Aurelith** war ihr größtes lebendes Werkzeug: ein wandelnder Astral-Ofen in Titanengestalt, dessen Sonnenprisma-Herz losen Dünensand unter gigantischem Druck zu reinem Sinterquarz und Tempel-Monolithen verschmolz.
* **Die Spaltung der Ventile:** Als das Reich zerfiel, staute sich in Aureliths Kern so viel ungebändigte Licht- und Erdmagie an, dass ein unkontrollierter Ausbruch die gesamte Nordwüste in totes, glühendes Glas verwandelt hätte. Um dies zu verhindern, schritt der Titan weit hinaus ins einsamste Dünenbecken der Singenden Quarzfelder, versenkte seinen Körper tief im Sand und **spaltete einen Teil seiner Ladung in sechs kleine [Quarzwächter](../../src/entities/enemies/quartz_golem.gd) ab**, die seitdem wie lebendige Blitzableiter und Druckventile über den umliegenden Quarzadern wachen.
* **Der Auslöser:** Wird ein Wächter zerschlagen, reißt sein Rückflusskanal wieder auf: Seine gespeicherte Energie strömt unaufhaltsam zurück in das versunkene Herz. Fallen alle sechs Wächter, gibt es kein Ventil mehr — Aurelith setzt seinen Riesenleib aus Sand, Goldrunen und Sonnenquarz selbst neu zusammen.

---

## 3. Visuelles Design & die 3 Metamorphosen

**Maßstab & Silhouette:** Kolossales, frei schwebendes Astral-Quarz-Wesen mit **`~156–162 px` Gesamthöhe** (Boden `(0,0)` bis Spitze der 9-teiligen Kathedral-Krone) und **`~168 px` Spanne** (über `~3,8×` so groß wie Ellie `42 px` und `~5,5×` so groß wie ein kleiner Quarzwächter `29 px`). Gebaut als rein organisches, prozedural 3/4-projiziertes (`SQUASH = 0.72`), tiefensortiertes Pixel-Art-Rig (`AurelithRig`) aus zackig abgeschlagenen Canyon-Sandstein-Massen (keine Fabrik-Quader, keine Roboterbeine), geschichteten Fels-Strata, glühenden Bruchrissen, facettierten Quarz-Drusen und getrenntem weltbeleuchtetem `Body` sowie unbeleuchtetem additivem `Glow`.

### Farb- & Material-System (`docs/design_guide.md` & `tools/art_desert_ruins.py`)
* **Geschichteter Wüstensandstein:** 1-px-Kontur `#241626` (nie `#000000`), Schatten `#483038` → `#785042` → Ocker `#aa7a4e` → Sonnenfläche `#d8a868` → NW-Grat `#f2cf8e`, belebt durch deterministische horizontale Schicht-Cluster, Abbruchkanten und magische Rissverzweigungen (Licht stets von links oben).
* **Antikes Ruinengold:** `#6f5020` → `#b48a38` → `#e6c468` → `#fff0b0` für Brustbögen, Schulterklammern, Kronenfassungen und Armillar-Ringe.
* **Facettierter Sonnenquarz:** Kontur `#282238`, Tiefenschatten `#364262` → `#5b698e` → `#8191b6` → `#a2b3d4` → `#d6e2f5` → scharfer NW-Lichtgrat `#ffffff` mit innerer Brechungsglut.
* **Strömende Magie nach Kampfphase:**
  * **Stage 1:** Strahlendes **Türkis & Sonnengold** (`#2a8c94`, `#78f4e6`, `#d0fff8` + `#ffe488`).
  * **Stage 2 (`prism_release`):** Aufgebrochenes **Weiß-Gold & Arkan-Violett/Magenta** (`#6636ad`, `#b47aff`, `#ff8ae2`, `#78f4e6`, `#fff0b0`).
  * **Stage 3 (`storm_ascension`):** **Zenit-Quarzgewitter** (`#ffe488`, `#ff7847`, `#cbaaff`, `#78f4e6`, `#ffffff`) samt kegelförmigem `96 px` Goldsand-Sturmtrichter (`#472c38` → `#f7de9e`).

### Die vier Gestalten im Lebenszyklus
1. **Schlafender Ruinen-Steinhügel (`Pose.DORMANT`):** Halb im Wüstensand versunkenes Monument (`~92 × 68 px`): breite, vom Wind geriffelte Sanddüne, schief aufragende Hörner-Obelisk-Maske mit erloschener 3-Augen-Fuge, versunkene Canyon-Schultern und schräg herausschießende rohe Quarzdrusen. Mit jedem besiegten Wächter (`soul_charge = 0.0..1.0`) glimmen Goldrunen auf, weiß-türkise Risse brechen durch das Gestein, und Sandkörner beginnen schwerelos nach oben zu schweben.
2. **Stage 1 — *Der Erste Monolith* (100 % – 66 % LP):** Kein humanoider Roboter, sondern ein schwebender uralter Berggeist: Unten ein **nach unten spitz zulaufender, geborstener Geoden-Stachel** über einem rotierenden Boden-Runensiegel, umkreist von **5 frei schwebenden Monolith-Schuppen**. Darüber ein V-förmig gespaltener Felsen-Brustkorb mit dunkler Kristallhöhle für das 8-strahlige **Sonnenprisma-Herz** + knisternde Arkus-Blitze, gewaltige Tafelberg-Schultern mit je 6 Quarzspitzen, **geflochtene 3-strängige Kraftbänder** zu riesigen **4-Klauen-Felsfäusten** (`~38 × 46 px`) und eine gehörnte **3-Augen-Obeliskenmaske** unter einer **9-splitterigen Kathedral-Krone**.
3. **Stage 2 — *Das Entfesselte Prisma* (66 % – 33 % LP):** Der äußere Sandsteinmantel sprengt auseinander (`DER MANTEL BRICHT`). Die Brustrippen und Schultern driften weit auseinander und legen das blendende Geoden-Herz frei; hinter Rücken und Schultern fächern sich **8 monumentale Prismen-Schwingenklingen** samt **12 kreisenden Satelliten-Splittern** auf; alle Kraftbänder brennen in Arkan-Violett, Weiß-Gold und Türkis.
4. **Stage 3 — *Herz der Singenden Dünen* (33 % – 0 % LP):** Nach dem Blitzschlag (`DIE SONNENSCHMELZE`) lösen sich unterer Kristallstachel und Schwebesteine in einen **tosenden, kegelförmigen 3D-Sandzyklon (`96 px` breit)** mit `10` wirbelnden Felssplittern auf. Um den schwebenden Koloss rotieren **zwei gewaltige geneigte Stein- & Gold-Armillarringe** (wie in der Zenitwarte) samt Zwillings-Prismenklingen (`~86 px`) an beiden Armen.

---

## 4. Standort (`Tile 626, 69`) & Das Erwachens-Ritual

* **Geprüfter Ort:** **Hoher Norden der Singenden Quarzfelder (`Tile 626, 69`, Region 33)** — ein weites, völlig flaches `L0`-Dünenbecken, über `100 Tiles` entfernt von Oasen, Karawanenstraße, Zenitwarte und jedem anderen Landmark.
* **Freie Welt-Platzierung:** Kein Tor, keine Quest-Freischaltung. Wer ab Tag 1 dorthin vordringt, sieht ein `~22 × 22` Tiles freies Dünenrund, sechs sternförmig zulaufende Bodenquarz-Adern, das versunkene Monument in der Mitte und **sechs kleine [Quarzwächter](../../src/entities/enemies/quartz_golem.gd)** (alle 3 Farbvarianten).
* **Der Seelen-Sog (6-Schritt-Trigger):**
  * **Wächter 1–2:** Tiefes gläsernes Summen setzt ein; Bodenrunen unter dem Sandhügel erwachen.
  * **Wächter 3–5:** Übrige Wächter werden aggressiver; Sandkörner und Steinchen schweben um das Monument nach oben; Lichtfugen brechen auf.
  * **6. Wächter fällt:** **0,8 s absolute Totenstille** (auch der Wüstenwind schweigt). Dann schießen die Energieströme aller 6 besiegten Wächter spiralförmig in den Hügel — Aurelith reißt sich aus dem Boden (`Pose.AWAKEN`), rammt beide Koloss-Fäuste in den Sand und treibt rund um das Becken (Radius `~290 px`) einen **Sinterquarz-Zahnring mit wirbelnder Sandsturm-Barriere** hoch (inkl. Klettersperre gegen Klippen-Abkürzungen).
* **Reset & Revanche:** Sterben alle Spieler oder verlässt niemand lebend das Becken, zerfällt der Quarzring wieder in freien Sand und das Monument fällt in `DORMANT` mit seinen 6 Wächtern zurück. Nach dem ersten Sieg bleibt stattdessen ein **Quarz-Projektorsockel** für direkte Revanchen ohne Vorkampf zurück.

---

## 5. Kern-Systeme des Kampfes

### 5.1 Bodenmagie: *Schmelze & Bruch* (`Sand ↔ Quarz`)
Aurelith verwandelt aktiv die Oberflächen der Arena (verzahnt mit `terrain.json`, wo `sand` `0.94x` und `quartz` `1.04x` Tempo gibt):
* **Treibsand-Mahlströme:** Ziehen Spieler sanft ins Zentrum, kosten beim Gegenansprinten mehr Ausdauer und lassen langsam sinken.
* **Verglaster Sinterquarz & Stehende Monolithen:** Brennstrahlen und tektonische Ausbrüche verschmelzen losen Sand temporär zu leuchtenden Sinterquarz-Platten (`1.04x` Laufgeschwindigkeit, schnelleres Zauberstab-Laden, kein Treibsand) und hohen **Quarz-Pfeilern** (Deckung vor Dünenwellen & Brennstrahlen).
* **Echter Tagesschatten (`day_canopies`):** Aureliths riesiger Körper und seine stehenden Quarz-Pfeiler werfen tagsüber echten Schatten, in dem Ellie mitten im Gefecht vor `SONNENHITZE` abkühlen kann.
* **Gegenspiel:** Quarzflächen leiten Aureliths *Resonanz-Impulse* weiter, und wuchtige Hammerschläge zertrümmern stehende Quarz-Pfeiler in Schrapnell-Explosionen zurück zu Sand.

### 5.2 Die kleinen Quarzwächter als aktive Kampf-Werkzeuge
1. **Geoden-Saat:** Schleudert glühende Quarz-Geoden ins Feld, aus denen 2–3 kompakte `Quarzwächter` (`~28–32 LP`) entstehen.
2. **Arkanes Spannnetz (Tether-Ketten):** Knisternde Energiestrahlen spannen sich zwischen Aurelith und seinen lebenden kleinen Golems und schneiden als bewegliche Barrieren über die Arena.
3. **Prisma-Strahlbrechung (ab Stage 2):** Schwenkt der große Brust-Brennstrahl durch einen lebenden kleinen Golem, **bricht dieser das Licht wie ein echtes Prisma in 3 rotierende Teilstrahlen**!
4. **Kolossale Rückschmelze:** Überlebt ein kleiner Golem zu lange, saugt Aurelith ihn in seine Faust und schleudert ihn als springende 3-Ringe-Kristallnova.
5. **Spieler-Konter („Resonanz-Kern“):** Jeder im Kampf besiegte kleine Golem hinterlässt für `5 s` einen instabilen **Resonanz-Splitterkern**. Ein Schlag oder Zauber in Richtung Aurelith katapultiert den Kern ins Ziel, durchschlägt Rüstung und unterbricht/bricht gefährliche Aufladungen — alles **gleichwertig mit Schwertern und Zauberstäben**.

---

## 6. Komplettes 3-Stage-Moveset (Endgame-Pinnacle)

Alle Angriffe nutzen präzise Boden-Warnflächen im Sinne von `docs/design_guide.md` mit klarem Aim-Lock-Fenster für Ausweichschritte (`Schattenschritt`).

### Stage 1 (100 % – 66 % LP): *„Der Erste Monolith“*
1. **Losgelöster Amboss-Schlag (`GAUNTLET_SLAM`):** Löst die rechte Koloss-Faust vom Körper, schwebt über das Ziel, schlägt mit Wucht ein, bleibt `2.5 s` als Deckung stecken und wird dann an der Energiekette **flach über den Sand zurückgerissen** (zweiter Hit auf der Rückzugslinie).
2. **Tektonische Quarz-Naht (`FAULT_SLAM`):** Drei verzweigte Bodennähte rasen fächerförmig nach vorn und lassen Quarzspitzen ausbrechen; die Endspitzen bleiben als stehende Quarz-Pfeiler stehen.
3. **Treibsand-Sog & Kathedralen-Ausbruch (`SINKHOLE_CAST`):** Verflüssigt unter den Zielen ein großes Sandbecken zum Mahlstrom, in dessen Mitte nach `1.1 s` ein riesiger Quarz-Obelisk aus dem Boden schießt.
4. **Kolossale Kristall-Klinge (`BLADE_CLEAVE`):** Lässt ein `86 px` langes Sonnenquarz-Großschwert aus der rechten Klauen-Faust wachsen — doppelter Weitschnitt + Überkopf-Spalter mit glühender Fulgurit-Spur.
5. **Geoden-Saat & Spannkette:** Beschwört 2 kleine `Quarzwächter` an Tether-Leinen, deren zurückgeworfene Kerne erstmals seine Panzerung knacken.

### Phasenwechsel 1 ➔ 2 (66 % LP): `DER MANTEL BRICHT`
Druckwelle, abplatzende Sandstein-Brustplatten, Auffächern der 6 Rücken-Prismenflügel, Wechsel auf weiß-violett-türkises Prismenfeuer.

### Stage 2 (66 % – 33 % LP): *„Das Entfesselte Prisma“*
1. **Solarer Brennstrahl & Prisma-Brechung (`CHEST_BEAM`):** Schwenkt einen konzentrierten Bruststrahl quer über die Arena (verglast Sand zu Fulgurit). Quarz-Pfeiler blocken ihn kurz vor dem Schmelzen; **lebende kleine Golems spalten ihn in 3 Sekundärstrahlen auf!**
2. **Tempel-Presse (`CLAP_PREP` ➔ `CLAP_CRUSH`):** Zwei massive Sandstein-Wände erheben sich beidseitig eines Ziels und knallen horizontal zusammen — seitlich ausbrechen oder per präzise getimtem `Schattenschritt` durch die Wand blinzeln!
3. **Synchrone Wächter-Triade:** 3 kleine Wächter spannen mit Aurelith ein Dreiecks-Lichtgitter bzw. einen synchronen `QuartzShard`-Sperrfeuerkreis; jeder zerstörte Eck-Wächter reißt eine große Sicherheitslücke auf.
4. **Magnetische Rückschmelze:** Opfert verbleibende kleine Golems zu einer springenden 3-Ring-Kristallnova (Innen → Außen → Mitte).
5. **Wandernde Sand-Mirage:** Zerfällt kurz in einen rasenden Goldsand-Strom über die Arena und bricht am Zielort mit einem 360°-Quarzschock neu hervor.

### Phasenwechsel 2 ➔ 3 (33 % LP): `DIE SONNENSCHMELZE`
Ein trockener Himmelsblitz schlägt direkt in das offene Prisma-Herz ein; das Wetter im Becken kippt sofort in ein lokales **Arkanes Quarzgewitter**, Beine zerfließen zum **Sand-Zyklon**, zwei Armillarringe beginnen zu rotieren.

### Stage 3 (33 % – 0 % LP): *„Herz der Singenden Dünen“*
1. **Dünentsunami & Wellenbrecher:** Eine komplette Arenabreite rollende Sand- & Glassplitterwand fegt zweimal aus wechselnder Himmelsrichtung durch das Becken — Schutz findet man nur im keilförmigen Windschatten der kurz vorab aufsteigenden Quarz-Wellenbrecher.
2. **Zwillings-Prismenklingen (`BLADE_CLEAVE` Twin):** Zwei `86 px`-Klingen an beiden Klauen für 3 schnelle Zyklon-Anstürme mit kreuzförmig detonierendem X-Schnitt aus Zeitbomben-Quarz.
3. **Astrales Armillar-Gericht:** 4 gegenläufige Runenringe mit wandernden Lücken um das Zentrum, während im Takt trockene Gewitterblitze auf vergangene Spielerpositionen niederfahren.
4. **Die Große Rückschmelze — `ZENIT-NOVA` (`ZENITH_CHARGE`):** Steigt im Zentrum auf und lädt eine `12 s` lange Kernschmelze auf, während `4–6` kleine Wächter vom Sturmrand einmarschieren, um sich in ihn zu stürzen. **3 mit Waffen oder Zaubern zerschlagene und zurückgeschmetterte Resonanz-Kerne sprengen seinen Zyklus auf** ➔ **`OVERHEAT STAGGER` (`Pose.STAGGER`)**: Aurelith bricht für `3.5 s` mit weit geöffnetem Herz-Prisma ein und nimmt massiven Kernschaden. (Schafft man nicht alle 3 Kerne, lässt sich die geschwächte Nova knapp hinter einem Rand-Monolithen überleben.)

---

## 7. Belohnung, Revanche & der 6-Pakete-Plan

### Beute & Weltkarten-Integration
* **Tod:** Kein blutiges Zerplatzen — die schwebenden Steine verlieren schwerelos ihren Halt, sinken mit einem tiefen Windharfen-Akkord in den Sand, und eine goldene Lichtsäule bringt das legendäre **Glutreliquiar** (`LootChests.boss_chest`) herab.
* **Einzigartiges Boss-Relikt (`BossRelics`, 100 % beim ersten Sieg pro anwesendem Spieler):**
  * **Armband `Fessel des Ersten Schmelzers`** (`bracelet`, Domäne `ANGRIFF`): Erhöhter Wuchtschlag & Aufladetempo + Perk **`PRISMENBRUCH`**: *Nach einem Schattenschritt bleibt am Ausgangspunkt eine geladene Sonnenquarz-Spitze zurück, die nach 0,6 s in Kristallsplittern detoniert — und Treibsand sowie Wüstenhitze verlangsamen dich nicht mehr.*
* **Weiterer Loot:** Hochwertige Kristallmaterialien + Handwerksmaterial **`Ur-Prisma der Schmelze`** (für späte Endgame-Zauberstäbe/Klingen in Stufe 7) sowie viel XP & Münzen.
* **Revanche & Karte:** Dauerhafter **Quarz-Projektorsockel** in der Mitte des Singenden Beckens (`ERNEUTER KAMPF BEREIT`) + eigener Wüstenboss-Marker auf der Weltkarte (`M`).

### Gebündelter 6-Pakete-Umsetzungsplan
| Paket | Fokus | Status |
|---|---|---|
| **Paket 1** | **Master-Dossier (`docs/enemies/boss_aurelith.md`), 3-Stufen-Facetten-Rig (`AurelithRig`) & OpenGL3-Vorschau (`tools/preview_aurelith.tscn`)** | **In Arbeit (aktuell)** |
| **Paket 2** | **Das Singende Becken (`Tile 626, 69`), 6 Wächter, Seelen-Sog-Trigger, Selbst-Erschaffung & dynamischer Quarz-/Sturmwall** | Offen |
| **Paket 3** | **Kampf-Fundament (Host/Koop), Bodenmagie (`Sand ↔ Quarz`, Treibsand, Tagesschatten) & Stage 1 (`100 %–66 %`)** | Offen |
| **Paket 4** | **Phasenwechsel `DER MANTEL BRICHT` & Stage 2 (`66 %–33 %`, Brennstrahl mit Golem-Prisma-Brechung, Tempel-Presse, Triade)** | Offen |
| **Paket 5** | **Phasenwechsel `DIE SONNENSCHMELZE` (lokales Quarzgewitter) & Stage 3 (`33 %–0 %`, Tsunami, Zwillingsklingen, Armillar-Gericht, `ZENIT-NOVA`)** | Offen |
| **Paket 6** | **Harmonischer Zerfall, Synthetische Audio-Suite (`tools/audio_*.py`), `Glutreliquiar`, Armband-Relikt, Hologramm & Testsuite** | Offen |
