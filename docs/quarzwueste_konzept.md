# Die Magische Quarzwüste – Konzept („Sonnenquarz-Öde“)

> Arbeitsnamen **Sonnenquarz-Öde** / **Die Singenden Dünen** (`biome: "quartz_desert"`). Alle Eigennamen und Zahlenwerte sind Startwerte zum gemeinsamen Abstimmen. Status: **Stufe 1 + Relief/Quarz/Wind-Sand + Wüstenflora + 4 variable Quarzoasen mit Sonnenpalmen & abbaubaren Sonnenquarz-Felsen (13 Arten, 11 Items, ohne umgefallene Baumstämme) gebaut (2026-11-13)** – Weltkarte (`165.784` Tiles in Überregion 6 / Regionen `5, 6, 32, 33, 34` mit nahtloser Land-Anbindung im Westen an *Das Leerenblühen*), 96-Tile-Übergang (`g_arid`), dynamisch mit `WorldWind` ziehende Sanddünen & Sandfahnen (`g_wind_sand`), seltene organische **strahlend weiße** Quarz-Ausbisse (~3,6 % Fläche, Tag & Nacht leuchtend), Sandstein-Wandtexturen (`Style 6`), **4 variable Quarzoasen im Wassersystem (`oasis_west`, `oasis_lagoon`, `oasis_twins`, `oasis_spring`)** mit grünem Ufersaum, klarem Türkiswasser, Sonnenpalmen, Quarzschilf, Quellblumen sowie die abbaubaren Sonnenquarz-Felsen (`sun_quartz_rock`) sind live; Wetter, Hitze, Hauptort und Zauberstab-Überarbeitung folgen in den nächsten Stufen.

---

## 1. Idee in drei Sätzen

Weit im hohen Norden der Welt geht das grüne Land über eine lange, ausdörrende Dornensteppe in eine **großflächige, flirrend heiße Sand- und Quarzwüste** über. Es ist keine tote Standardwüste: Uralte Magie hat den Sand stellenweise zu **weißen, goldenen und violett-türkisen Sinterquarz-Platten** verschmolzen, halb versunkene **Quarzruinen** durchziehen die Dünen, und statt Regen entladen sich **arkane Quarzgewitter**, die vergessene Siegelkreise und **magische Quarz- und Steinkolosse** wecken. Spielerisch ist die Wüste ein deutlich schwereres Spätspiel-Biom mit spürbarer **Mittagshitze** (Ausdauerdruck und eigenes Verhalten bei Ellie) und bildet später den zentralen Ankerpunkt, an dem das Zauberstab-System mit neuen Stabtypen und echter Kristall-Veredelung richtig Fahrt aufnimmt.

---

## 2. Leitgedanken

- **Groß, weit weg und eigenständig:** Überregion 6 im hohen Norden/Nordosten, rund **80.000 bis 90.000 Tiles** groß (über **doppelt so groß wie der Hexenwald**, aufgeteilt in **3 Regionen** `32–34`). Der Einstieg liegt rund **420–620 Tiles nördlich von Glimmrast** `(786, 676)` – also etwa viermal so weit entfernt wie der Hexenwald und klar als späteres Expeditionsgebiet positioniert.
- **Neu angebacken, Altland 100 % unangetastet:** In der großen Nordost-Bucht des bestehenden `1100 × 1100`-Weltrasters (`x 585..1076, y 24..340`) liegen über `128.000` freie Wasser-/Leere-Tiles. Wie beim Hexenwald wächst das neue Land breit aus der Nordküste (Regionen 5 und 6), ohne ein einziges Pixel Altland, einen bestehenden See, einen Fluss oder Mornaths Arena `(499, 258)` zu verändern. Auch die Weltgröße `1100 × 1100` bleibt erhalten, sodass Streaming, Shader und Spielstände nahtlos weiterlaufen.
- **Langer, organischer Übergang statt harter Grenze:** Kein plötzlicher Farbwechsel. Über **~96 Tiles** (aufgebrochen durch lange Windzungen) trocknet die Wiese erst zu goldener Strohsteppe aus, reißt dann in warmen Ockerlehm mit verwehten Sandstreifen auf und öffnet sich schließlich ins weite Dünen- und Quarzland.
- **Kontrast zum Hexenwald, Brücke zur Lore:** Der Hexenwald im Süden ist kalt, eng, neblig und dauerdämmrig; die Quarzwüste im Norden ist weit, gleißend warm, schattenarm und nachts sternenklar voller nachglimmender Quarzadern. Lore-Brücke zu Ilva (`docs/seehexe_konzept.md`): Wo rohe Magie und Druck aufeinandertreffen, wird Licht zu Kristall gepresst – hier geschah das vor langer Zeit im Maßstab einer ganzen Landschaft.
- **Neue Gegnerfamilie statt nur Schattenwesen:** Neben nächtlichen Gefahren erwachen aus den Quarzruinen **magische Konstrukte, Stein- und Quarzkolosse** mit völlig eigenem Kampfgefühl (Lichtbrechung, Kristallpanzer, Erd- und Strahlenangriffe).
- **In der Wüste regnet es nie:** Globales Regen- und Sturmwetter wird im Biom vollständig abgefangen und in trockene Hitzewinde, **Resonanzstürme** und **arkane Quarzgewitter** übersetzt.

---

## 3. Lage, Größe und innere Zonen

### 3.1 Geografie auf der Weltkarte

```text
                      ┌──────────────────────────────────────────────────┐
                      │   ÜBERREGION 6: MAGISCHE QUARZWÜSTE (~85k Tiles) │
                      │   R33 Quarzfelder & Oase  │  R34 Tiefe Ruinenöde │
   [Das Leerenblühen] │           ▲               │          ▲           │
     Arena (499,258)  │   R32 Dornensaum & Golddünen (langer Übergang)   │
                      └───────────┴───────────────┴──────────┴───────────┘
                                  Anschluss Nordküste (R5 / R6, y ≈ 204..240)
   [Glasklippen]                  [Versunkene Ruinen (noch Wiese)]
   Hallgrat (150,350)                        │
   [Die Lichtung]                 [Nebelwald / Glimmrast (786,676)]
                                             │
                                      [Hexenwald (820,891)]
```

| Kennwert | Planungswert |
|---|---|
| **Überregion / Regionen** | `super: 6`, übernimmt die unbebauten Nordregionen `5` & `6` (`40.957` Tiles) + neue Nord-/West-/Ost-Regionen `32`, `33` & `34` (`124.827` Tiles), `own_biomes: ["quartz_desert"]`, Biom-Byte `206`, nahtlos zu Land an *Das Leerenblühen* (`R0, R1, R4`) und *Versunkene Ruinen* (`R5, R6`) angebunden |
| **Hüllbox & Fläche** | `x 368..1072`, `y 24..408`, insgesamt **165.784 Tiles** (über **4,3× so groß wie der Hexenwald** mit `38.158` Tiles; *Versunkene Ruinen* behält südlich davon weiter 4 große Regionen mit `73.136` Tiles) |
| **Geprüfte Baufreiheit in R5 & R6** | **0 Flüsse**, **0 Seen** (nächster See erst bei `y = 429`), **0 Hütten/Quests/Rätsel**; einziger Punkt ist der bestehende Wegstein *Wächterin der Versunkenen* `(915, 308)`, der als natürliches Tor im südlichen Übergangssaum erhalten bleibt |
| **Abstand zu Orten** | Saum ab ~294 Tiles, Zentrum ~500 Tiles nördlich von Glimmrast `(786, 676)`; >120 Tiles Abstand zu Mornaths Boss-Arena `(499, 258)` |

### 3.2 Die drei Teilregionen (Steigerung von außen nach innen)

1. **Region 32 – Dornensaum & Golddünen (Südwesten / Einstieg):**
   Der lange Übergangsgürtel aus der nördlichen Küstenwiese über Strohgras und Ockerlehm hinein in weite, vom Wind geformte Gold- und Bernsteindünen, erste Sandstein-Tafelberge (*Mesas*) und vereinzelte verwitterte Grenzsteine.
2. **Region 33 – Die Singenden Quarzfelder & Quarz-Oase (Mitte / Nordwesten):**
   Offene Sandflächen wechseln sich mit großen Decken aus **Sinterquarz** ab – spiegelglatte, facettierte Kristallplatten und aus dem Boden brechende Quarzrippen, die im Wind leise singen. In einer geschützten Felssenke liegt eine **türkisklare Quarz-Oase** (`lakes.json` `ponds`) als einziger natürlicher Schatten- und Kühlungsort.
3. **Region 34 – Das Versunkene Ruinenfeld (Nordosten / schwerste Zone):**
   Höhere Sandstein-Plateaus, tiefe Canyons, dichte Quarzadern und überall im Sand halb begrabene **magische Quarzruinen** (gebrochene Prismenbögen, Lichtleit-Rinnen im Stein, alte Siegelplatten, Obelisken-Stümpfe). Hier schlagen arkane Gewitter am stärksten ein und hier wachen später die großen Quarz- und Steinkolosse. *(Ein zentraler Hauptort wird hier später separat ergänzt.)*

---

## 4. Übergang, Boden- und Quarztexturen (Herzstück von Stufe 1)

### 4.1 Der dreistufige Übergang (`BiomeBlend` Kanal `g_arid`)

Damit sich der Weg in die Wüste wie eine echte Klimareise anfühlt, erhält `BiomeBlend` (`src/world/biome_blend.gd`) neben `g_gloom` (Hexenwald) ein zweites Feld **`g_arid`** (`fade: 96.0` Tiles, also doppelt so lang wie beim Hexenwald). Im Boden-Shader wird die Kante zusätzlich mit gerichteten Wind-Zungen überlagert, sodass Sandstreifen in den Saum hineinwehen und Grasinseln in geschützten Mulden länger durchhalten:

| Phase | `arid`-Wert | Strecke | Sichtbares Bodenbild |
|---|---|---|---|
| **0. Wiese** | `0.00` | Altland | Unverändertes saftiges Wiesengrün (`RAMP`) |
| **1. Sonnenstroh-Steppe** | `0.05 – 0.38` | Tile `0..35` | Grün trocknet über Salbei zu warmem **Goldstroh** (`STEPPE`); Grashalme im Shader werden kürzer (2 px), spärlicher und strohgelb; erste flache Sandflecken |
| **2. Rissiger Ockerlehm & Sandzungen** | `0.38 – 0.72` | Tile `35..70` | Gras zieht sich auf kleine Büschel zurück; warmer **Ocker-/Terrakottalehm** mit trockenen Rissen und langgezogenen **Dünensand-Zungen**; Schritte stauben leicht |
| **3. Quarzwüste** | `0.72 – 1.00` | ab Tile `70+` | Reiner, windgeriffelter **Gold- und Bernsteinsand** (`SAND`), durchzogen von gewachsenen **Sinterquarz-Platten und Kristalladern** (`QUARTZ`) |

### 4.2 Farbpaletten (6 Stufen dunkel → hell, abgestimmt auf Shadowspore)

Alle Schatten behalten gemäß `docs/design_guide.md` einen leicht kühl-violetten/pflaumenfarbenen Unterton statt schmutzigem Grau, damit Charaktere, Beute und Magie perfekt darauf stehen:

| Stufe | **Strohsteppe (`STEPPE`)** | **Wüstensand (`SAND`)** | **Facettenreicher Sonnenquarz (`QUARTZ_W`)** |
|---|---|---|---|
| 0 (tiefster Schatten) | `#3a3130` | `#472c38` *(warmes Pflaume-Umbra)* | `#5b698e` *(kühle Kristallfuge / SE-Fasen)* |
| 1 | `#544838` | `#6b433e` | `#8191b6` *(Schatten-Kristallfläche)* |
| 2 (Basis dunkel) | `#746443` | `#946247` | `#a2b3d4` *(milchiger Quarzkörper)* |
| 3 (Basis hell) | `#988452` | `#bd8754` *(Goldocker)* | `#bfcde7` *(heller Kristallschliff)* |
| 4 (Sonnenkante) | `#bca668` | `#dfb06e` *(warmer Bernsteinsand)* | `#d6e2f5` *(hellweißes Sonnenfeld)* |
| 5 (Spitzenlicht) | `#dcc988` | `#f5d596` *(heller Dünenkamm)* | `#ffffff` *(scharfer NW-Grat & Lichtfunke)* |

**Kartenfarbe (`data/biomes.json`):** `#d9a45b` (warmes Wüstengold mit klarem Abstand zu Wiese `#5fb36b`, Glasklippen `#8a6fd6`, Leerenblühen `#c9506f` und Hexenwald `#4d5f72`), mit eigenen Kartensymbolen (Dünenwelle, Quarzspitze, gebrochener Bogen).

### 4.3 Dynamischer Wind-Sand & natürliche, facettierte Quarz-Ausbisse

Gemäß `docs/design_guide.md` wird kein verrauschtes Einzelpixel-Korn und kein künstliches Schachbrett-Raster gezeichnet, sondern organische, gerichtete Pixelformen (Licht von links oben):

1. **Dynamische Anbindung an `WorldWind` (`g_wind_sand` + `ground_tone.gdshader`):**
   - `WorldWind` integriert den Dünenwind im festen Passat-Bezugssystem (`s_dir = (0.9653, 0.2612)`) ohne Weltursprungs-Rotationshebel in das Shader-Uniform `g_wind_sand` (`sand_drift.x`, `dune_creep`, `desert_push`) und spawnt spärliche goldene Sandwischer sowie vereinzelt matte `1×1`-Kristallkörnchen tief über dem Sand (`kind = 9`, ohne nach oben schießende weiße Blitze).
   - Im Boden-Shader wandern die geschwungenen **Dünen-Rippelkämme** (`dune_ripple`) langsam mit dem Wind, Dünenkämme atmen subtil in Windrichtung, und bei Böen fegen weiche **Sandfahnen / Schleierbänder** (`ribbon_a` / `ribbon_b`) ruhig über die offenen Golddünen.
   - **Beruhigtes Licht-Ambiente (`DayMotes` & `Fireflies`):** In der Wüste steigen keine schnellen Wiesenpollen oder hellen Glühwürmchen-Kreuze auf – stattdessen schweben nur wenige, stark gedimmte, nahezu stationäre `1×1`-Hitzeflimmer- und Kristallfunken bevorzugt über Quarzadern.
2. **Seltene, organisch gewachsene, polygonal facettierte Quarzadern (`quartz_field` + `quartz_voronoi`):**
   - Statt dichter regelmäßiger Platten bricht der Quarz nur auf **~3,6 % der Wüstenfläche** in mehrstufig domain-gewarpten Nestern und vereinzelten kleinen Splittern natürlich aus dem Sand.
   - **Klare Kristalltextur statt Einheitsweiß:** Jedes Quarznest besteht aus unregelmäßigen polygonalen **Voronoi-Kristallfacetten**, scharfen **1-px-Bruchfugen & NW-Lichtgraten**, gerichteten Wachstumsstreifen und sandverwehten Randkerben. Die sechs Helligkeitsstufen (`QUARTZ_W[0..5]`) sind exakt auf `day_grade` und `MoodGrade` kalibriert, sodass am Tag sowohl Fugen und Schliffe als auch reinweiße Grate plastisch bleiben; nachts zeichnet `floor_quartz_glow` denselben Kristallschliff im unbeleuchteten `Glow`-Pass nach.

### 4.4 Spürbarer Unterschied unter den Füßen (`data/terrain.json`)

| Oberfläche | Tempo (`speed`) | Schritt-Effekt (`step`) | Fußspuren (`footprint`) | Klang & Spielgefühl |
|---|---|---|---|---|
| **`steppe`** | `1.00` | kleiner trockener Staubpuff | blass, `4.0 s` | Trockenes Rascheln im Übergang |
| **`sand`** | `0.94` | warme Sandwölkchen (`#dfb06e`) | deutliche Dellen im Sand (`#7a5042`, `9.0 s`) | Weich, leicht einsinkend, gedämpfter Schritt |
| **`quartz`** | `1.04` | feiner heller Lichtfunken | keine Spur (glatter Stein) | Heller, gläsern-steiniger Klang; auf Quarzadern läuft man spürbar leichter! |

Damit werden die Quarzadern schon beim Durchqueren spielerisch sinnvoll: Wer auf den leuchtenden Quarzrücken läuft, kommt schneller durch das Dünenmeer voran und folgt oft ganz natürlich den alten magischen Kraftlinien.

---

## 5. Gelände, Sandstein-Klippen und Wege (Stufe 2)

- **Relief-Aufbau (nur auf Biom-Byte `206`):**
  - Rund **68 % Ebene 0** (weite Dünenbecken, Quarzfelder, Oasenmulde), **20 % Ebene 1** (flache Sandrücken und Quarzterrassen), **10 % Ebene 2** (geschichtete Tafelberge / *Mesas* und Canyons) und **2 % Ebene 3** (hohe Ruinenplateaus im Nordosten).
  - Verbinder: breite **Sandrampen** (vom Wind an Klippen angewehte Dünenhänge, 65 %) und **gemeißelte Ruinentreppen** aus hellem Quarzstein (35 %).
- **Neuer Wandstil 6 „Quarz-Sandstein“ (`assets/shaders/relief.gdshader`):**
  - Warme horizontale **Sandstein-Schichtung** (Ocker, Terrakotta, Pflaumenschatten) ohne grüne Graslippe an der Oberkante – stattdessen eine weiche, vom Wind überwehte **Sandkrone** oben und angewehter Sandfuß unten.
  - Schräg durch den Fels ziehen sich **kristalline Quarzadern**, die tagsüber in der Sonne glitzern (`g_sun`) und im `glow_pass` nachts sowie während arkaner Gewitter leise leuchten.
- **Die Quarz-Oase (`data/lakes.json` `ponds`):**
  - Ein rund `24 × 20` Tiles großes, türkisklares Quellbecken im Zentrum von Region 33, eingefasst von weißen Quarzstufen und schattenspendenden Sonnenpalmen. Watbares Flachwasser am Rand, tiefer Kern in der Mitte.
- **Alte Karawanen- und Ruinenstraße (`data/ground.json` `paths`):**
  - Kein frisch getrampelter Waldpfad, sondern eine **halb vom Sand verwehte Pflasterspur aus hellem Quarzstein**, die an der Nordküste von Region 5/6 beginnt, alle paar Dutzend Tiles unter Dünen verschwindet und wieder auftaucht und bis zur Oase und vor das östliche Ruinenfeld führt.

---

## 6. Klima: Mittagshitze, Ellies Verhalten und Magisches Wetter (Stufe 3)

### 6.1 Grundregel: In der Wüste regnet es nie

`WeatherManager` und `Moisture` fragen lokal `BiomeBlend.arid_at(pos)` ab:
- Ab `arid > 0.35` fallen **keine Regentropfen**, es entstehen keine Wasserpfützen, kein nasser Boden und kein Regen-Soundbett.
- Stattdessen übersetzt die Wüste die globalen Wettersegmente deterministisch (ohne extra Netzwerkverkehr, auf allen Peers identisch!) in **eigenes magisches Wüstenwetter**:

| Globale Wetterlage | In der Quarzwüste | Optik & Atmosphäre | Spielerischer Effekt |
|---|---|---|---|
| `clear` / `fair` | **Sengende Sonne** | Knallwarmes Goldlicht (`MoodGrade` Preset `desert`), dezentes Hitzeflimmern, glitzernde Quarzfacetten | Volle **Mittagshitze** in offener Sonne |
| `broken` / `overcast` / `gale` | **Dünenwind** | Ziehende Sand- und Goldstaubfahnen knapp über dem Boden (`WorldWind`), weicheres Ockerlicht | Hitzedruck halbiert, weitere Windspuren |
| `drizzle` / `rain` | **Singender Resonanzwind** | Statt Regen schweben **türkis-goldene Quarzfunken** im Wind; die Quarzplatten am Boden summen leise und glimmen am Tag | Zauberkristalle im Stab laden auf Quarzplatten **+20 % schneller** auf |
| `downpour` / `storm` | **Arkanes Quarzgewitter** | Violett-bernsteinfarbene Wolkenbänke, **trockene Magieblitze** zwischen Himmel und Quarzspitzen, kurz aufschwebende Kristallsplitter | Quarzruinen und Siegelkreise erwachen; Zauber laden stark beschleunigt, wecken aber Ruinenwächter in der Nähe |

### 6.2 Die Hitze-Mechanik (`SONNENHITZE`) & Ellies Reaktion

Leitsatz (wie beim Nebel im Hexenwald): **Die Hitze fordert, aber sie tötet nicht.** Kein nerviger Lebensabzug pro Sekunde, sondern spürbarer Druck auf Bewegung, Positionierung und Ausdauer:

- **Wann wirkt die Hitze?**
  Nur **tagsüber** (am stärksten in der Mittagszeit `0.34 .. 0.66` der Tagesuhr, skaliert mit `TimeManager.sun_amount()` × `arid`), und nur unter freiem Himmel. Nachts sinkt die Hitze auf `0` – die Wüstennacht ist kühl, klar und frei von Ausdauerdruck.
- **Spielerische Auswirkung (Status `sun_heat` / `ERHITZT`):**
  - Die **Ausdauer-Regeneration** ist in praller Mittagssonne um bis zu **30 % verlangsamt** und Sprinten/Schattenschritt verbrauchen **+15 % Ausdauer**.
  - Die **Ausdauerranke im HUD** (`SapVine`) bekommt bei starker Hitze einen warm-goldenen Schimmer am Rand.
- **Wie man es Ellie direkt ansieht:**
  - **Eigene Hitze-Standgesten (`player_standby` / `tools/art_hero3d.py`):** Steht Ellie erhitzt in der Sonne still, spielt sie statt des normalen Streckens eine neue 8-Richtungs-Geste ab: **Sie wischt sich mit dem Handrücken/Unterarm den Schweiß von der Stirn**, atmet im Idle etwas tiefer und fächelt kurz Luft an den Kragen.
  - Winzige helle Schweiß-/Hitzepixel nur während dieser Geste und ein dezenter warmer Ton auf der Sonnenkante.
- **Natürliche Abkühlung (sofortiges Gegenspiel in der Welt):**
  1. **Schatten suchen:** Im Wandschatten von Tafelbergen/Klippen, unter den Bögen alter Quarzruinen und unter Oasenpalmen (`g_day_cover` + Relief-Schattenprüfung) kühlt Ellie binnen **2–3 Sekunden** ab.
  2. **Wasser & Oase:** Waten am Rand der Quarz-Oase entfernt Hitze sofort und gibt kurzzeitig **ERFRISCHT** (normale + leicht erhöhte Ausdauer-Regeneration für 45 s).
  3. **Große Quarzplatten:** Kühler weißer Sinterquarz halbiert den Hitzeaufbau selbst in der Sonne.
  4. **Spätere Hilfsmittel:** Kühlende Frucht aus Glasaloe/Kaktusfeige, Wüstentrank oder Hitzeschutz-Talisman.

---

## 7. Pflanzenwelt, Quarzvorkommen und verstreute Ruinenmagie (Stufe 4)

Ab `arid > 0.35` wachsen keine Wiesenbäume, Tannen, Kleefelder, Waldpilze oder umgefallenen Baumstämme (`FallenLog`) mehr (`PropGenerator.DESERT_KINDS`). Mindestens ~85 % der offenen Sanddünen bleiben bewusst frei für Wind, Sichtweite und Orientierung; in der baumlosen Wüste liegen auch **keine umgefallenen Stämme**. Stattdessen wächst ein dreizoniges Wüsten-Ökosystem (Übergangssaum, Mesa-/Klippen-Kakteen, Quarzränder & offener Dünensand):

### 7.1 Implementierte Wüstenflora (9 Arten, 7 Items, `MeadowDetails` Slots 30–33)

| Pflanze | Art / Größe | Wo sie wächst | Ernte, Nutzen & Besonderheit |
|---|---|---|---|
| **Kronen-Säulenkaktus** (`crown_cactus`) | Großer Säulenkaktus (`tree.tscn`, 5 Varianten) | Geschützte Tafelberg-/Klippenfüße & Kakteen-Gärten | E-Pflücken gibt `crown_fig` (*Kronenfeige*); Axt fällt für `cactus_wood` (*Kaktusholz*) & `cactus_pulp` (*Kaktusmark*) |
| **Sonnenfeigen-Kaktus** (`prickly_pear`) | Feigenkaktus-Strauch (`bush.tscn`, 5 Varianten) | Klippenfüße, Kakteen-Gärten & trockene Hänge | E-Pflücken gibt leuchtende `sun_fig` (*Sonnenfeige*); Sichel gibt `cactus_pulp` & `plant_fiber` |
| **Sandigel** (`barrel_cactus`) | Gerippter Kugelkaktus (`flora.tscn`, 4 Varianten) | Zwischenglied an Hängen & Kakteen-Rändern | Sichel-Ernte liefert saftiges `cactus_pulp` (*Kaktusmark*) |
| **Wüstendorn** (`desert_scrub`) | Knorriger Dornenstrauch (`bush.tscn`, 6 Varianten) | Langer 96-Tile-Steppensaum & Dünenränder | Löst im Saum den Wiesenbusch ab; Sichel gibt `stick` & `plant_fiber` |
| **Steppenroller** (`tumble_scrub`) | Luftiger Trockenball (`flora.tscn`, 4 Varianten) | Saum & windoffene Dünenränder | Stäubt beim Durchstreifen goldene Samen (`puff`) im `WorldWind`; Sichel gibt `plant_fiber` & `stick` |
| **Dünengras** (`dune_grass`) | Windgebogene Goldgräser (`flora.tscn`, 5 Varianten) | Löst Wiesengras im Übergang & an Dünenkämmen ab | Hohe Windanbindung; Sichel gibt `plant_fiber` |
| **Glasaloe** (`glass_aloe`) | Durchscheinende Sukkulente (`flora.tscn`, 4 Varianten) | Ausschließlich am Rand der weißen Quarz-Ausbisse | Türkis leuchtende Kristallblätter; E-Pflücken gibt kühlende `quartz_aloe` (*Quarzaloe*) |
| **Königin der Nacht** (`night_cactus`) | Nachtblüher (`flora.tscn`, 4 Varianten) | Quarzränder & seltene Klippenfüße (`bloom: "night"`) | Tags als Knospe geschlossen, öffnet sich **nur nachts** leuchtend weiß-violett → `night_cactus_bloom` |
| **Sandknolle** (`sand_tuber`) | Verborgene Wüstenwurzel (`flora.tscn`, 4 Varianten) | Spärlich im freien Goldsand (`pull: true`) | Zweihändiges Herausziehen mit Goldsand-Burst (`soil_burst`) → `sand_tuber` (*Sandknolle*) |
| **Sonnenpalme** (`sun_palm`) | Schlanke Oasenpalme (`tree.tscn`, 6 Varianten inkl. Doppelstamm & Schirmkrone) | Grüne Quarzoasen-Ufer | Pflückbare goldene `sun_date` (*Sonnendattel*) + axtfällbar (`axe`) → `palm_wood` (*Palmenholz*) & `plant_fiber` |
| **Quarzschilf** (`oasis_reed`) | Feingefiedertes Schilf mit türkiser Tauspitze (`flora.tscn`, 5 Varianten) | Direkt an der Wasserlinie der Quarzoasen | Sichel-Schnitt (`sickle`) → `reed` & `plant_fiber` |
| **Quellblume** (`oasis_lily`) | Jadegrüne Uferrosette mit türkisgoldener Blüte (`flora.tscn`, 4 Varianten) | Grüne Uferpolster der Quarzoasen | Pflückbar (`PFLÜCKEN`) → heilende `oasis_blossom` (*Quellblüte*), leuchtet sanft nachts |

### 7.2 Abbaubare Quarz- und Ruinen-Rohstoffe (Spitzhacke)

- **Sonnenquarz-Fels (`sun_quartz_rock`, `rock.tscn`, 6 Varianten × 4 Stufen):** Warmer Sandsteinsockel mit klaren weiß-türkis-goldenen Quarzspitzen in Felsgruppen an Quarzadern/Klippen und als einzelne Ausbisse (mit Spitzhacke abbaubar → `sun_quartz` *Sonnenquarz* + `stone`, wächst in 3 Tagen nach).
- **Prisma-Ader (`prism_vein`, geplant):** Seltene, mehrfarbig schillernde Quarzdrusen in Region 33/34 → gibt **Prismensplitter** und rohe ungeläuterte Zauber-/Verstärkersteine höherer Güte.
- **Ruinen-Bruchstein (`ruin_sandstone`):** Behauene alte Sandsteinblöcke mit Goldfugen → für spätere Bau- und Handwerksrezepte.

### 7.3 Verstreute Quarzruinen-Elemente (aktive Umweltmagie in der Fläche)

Schon **bevor** wir später den großen Hauptort festlegen, ist die Wüste (besonders Region 33 & 34) von kleineren **magischen Ruinenfragmenten** durchzogen, die die „Heimsuchung durch Ruinenmagie“ auf Schritt und Tritt erlebbar machen:

1. **Lichtleit-Rinnen & Gebrochene Bögen:** Halb im Sand versunkene Torbögen und Steinrinnen mit eingelassenem Quarz. Wirkt Ellie in der Nähe einen Zauber (oder zieht ein Arkan-Gewitter auf), läuft ein heller Lichtimpuls die alte Leitung entlang bis zum nächsten Obelisken.
2. **Schlafende Resonanz-Obelisken:** Schräg aus der Düne ragende Quarzpfeiler. Manche summen ruhig und verkürzen im Umkreis von 5 Tiles die Aufladezeit des Zauberstabs; andere sind überladen und entladen in regelmäßigen Takten sichtbare **Prisma-Ringe** über den Sand.
3. **Alte Siegelkreise im Quarz:** Runde Steinplatten im Boden mit leuchtenden Runen – einige bergen vergrabene Beutetruhen oder Welt-Rätsel (`WorldTrial`-Anbindung wie ein Lichtstrahl-/Prismen-Rätsel), andere sind Ruheplätze von schlafenden Ruinenwächtern.

---

## 8. Natürliche Tierwelt der Wüste (Stufe 5)

Alle gewöhnlichen Tiere folgen den Regeln aus `docs/design_guide.md`: 8 echte Blickrichtungen aus dem 3D-Pixelrenderer, kein eigenes Leuchten, keine Kampf-/Tötungsmechanik, natürliches Flucht- und Ruheverhalten:

- **Wüstenfuchs / Fennek (`desert_fox`):** Kleiner, sand- und cremefarbener Fuchs mit übergroßen Ohren. Tagsüber zusammengerollt im Schatten von Felsen und Ruinenbögen schlafend; in der Dämmerung und nachts flink auf Nahrungssuche, lauscht mit drehenden Ohren nach Insekten im Sand.
- **Quarz-Eidechse (`quartz_lizard`, `TinyWildlife`):** Kleine türkis-sandfarbene Agame/Eidechse. Sonnt sich tagsüber auf warmen Quarzplatten und Ruinensteinen (Liegestütz-Nicken!), flitzt bei Annäherung blitzschnell in die nächste Felsspalte.
- **Wüstenbussard / Geier (`desert_hawk`):** Nutzt das bestehende Vogelflug-System mit weiten, langsamen Gleitkreisen in der heißen Aufwind-Thermik; landet auf hohen Tafelberg-Kanten, Kaktusspitzen und gebrochenen Ruinenpfeilern.
- **Gold-Skarabäus (`scarab`, `TinyWildlife` / `LeafCritter`-Verwandter):** Metallisch gold-türkis schimmernder Käfer, der kurze Spuren in den Dünensand zieht und sich bei schnellen Schritten eingräbt.

---

## 9. Neue Gegnerfamilie: Magische Quarz- und Ruinenwächter (Stufe 6)

Hier bricht das Biom bewusst das Muster „nur schwarze Schattenwesen“ auf und führt eine **zweite Hauptgattung** für das schwere Spätspiel ein: **Arkane Quarz- und Steinkonstrukte**, erschaffen aus verwittertem Wüstensandstein, altem Goldbeschlag und einem glühenden **Sinterquarz-Kern**, dessen magisches Feld die schwebenden Steinbrocken zusammenhält.

### 9.1 Gemeinsame Gestaltungs- und Kampfregeln der Ruinenwächter

- **Optik:** Warmer, geschichteter Sandstein + dunkel angelaufenes Ruinengold + **hell leuchtende Quarzkerne und Kraftlinien** in Weiß-Türkis, Goldbernstein und Arkan-Violett (`Unlit`-Maske für Kern und Fugen, Gestein normal weltbeleuchtet).
- **Am Tag UND in der Nacht aktiv:** Anders als Schattenwesen verbrennen Ruinenwächter nicht bei Sonnenaufgang! Tagsüber liegen viele von ihnen **getarnt als scheinbar leblose Ruinen-Steinhaufen oder eingeklappte Obelisken** im Sand und setzen sich erst mit einem tiefen Steinmahlen und aufblitzendem Quarzkern zusammen, wenn man in ihren Siegelkreis tritt oder daneben zaubert.
- **Lesbare Warnflächen (`design_guide.md`):** Alle Stein- und Strahlenangriffe kündigen sich über präzise Boden-Warnflächen an; beim Tod zerbirst das Magnetfeld in Quarzsplitter und lässt hochwertige Kristall- und Ruinenmaterialien zurück.

### 9.2 Die ersten drei geplanten Gegnertypen (Ausarbeitung in eigenem Gegner-Konzept)

1. **Quarz-Koloss (`quartz_colossus` – schwerer Ruinenwächter):**
   Massiver, breitbeiniger Koloss (ca. 56–68 px hoch) aus schwebend gekoppelten Sandsteinquadern mit einem offenen Prisma-Kern in der Brust.
   - *Angriffe:* **Quarz-Erdstoß** (schlägt die Faust in den Sand → eine Linie scharfer Quarzspitzen bricht verzögert auf das Ziel zu aus dem Boden), **Prismen-Beben** (runder Schockring, der lose Quarzbrocken hochschleudert) und **Brennstrahl** (bündelt Sonnen-/Arkanlicht aus der Brust in einem langsam schwenkenden Strahl).
   - *Taktik:* Während er den Brennstrahl auflädt, liegt sein offener Brustquarz frei (Schwachpunkt für schwere Treffer / Gegen-Schulen).
2. **Spiegel-Obelisk / Prismenwächter (`prism_sentinel` – taktischer Fernkämpfer):**
   Schwebender, dreiteiliger Quarz-Obelisk aus den Ruinen, der sich im Kampf wie eine Blüte aus Steinplatten auffächert.
   - *Besonderheit:* Seine polierten Quarzschilde **brechen oder reflektieren frontale Geschosszauber** während seiner Schildphase – zwingt zum Umrunden, Schattenschritt in den Rücken oder gezielten Nahkampf/Flächenzauber!
3. **Dünen-Skorpion / Quarzpanzer-Lauerer (`dune_stalker` – Hinterhalt im Sand):**
   Mit Quarzkrusten überwachsenes Wüstenwesen, das unter der Sandoberfläche lauert (nur eine kleine Quarzspitze ragt wie ein gewöhnlicher Sammelstein heraus!) und auf laute Schritte, Sprinten oder Zaubervibrationen im weichen Sand mit einem Ausbruch aus der Düne reagiert – wer auf festen **Quarzplatten** bleibt, verrät sich ihm kaum.

*(Nachts mischen sich am Küstenrand der Leere zusätzlich abgehärtete Schattenwesen unter die Ruinenkonstrukte – teilweise geraten Schattenwesen und erwachte Ruinenwächter sogar aneinander.)*

---

## 10. Späterer Ankerpunkt: Zauberstäbe, Veredelung & Hauptort (Stufe 7 – bewusst nachgelagert)

Diese Punkte sind als feste Leitplanken gesetzt, werden aber erst **nach dem Welteinbau der Wüste** in einem eigenen Konzept detailliert:

1. **Neustaffelung der Magie-Progression:**
   - **Frühes/mittleres Spiel bei Ilva (Seehexe):** Bodenständiger, klarer Einstieg – erste Holz-/Knochenstäbe, Läutern von Rohsteinen und einfache Schliffe (untere Stufen), ohne das System schon früh zu überfrachten.
   - **Spätes Spiel in der Quarzwüste:** Erst hier öffnet sich die **tiefe Kristall-Veredelung** (Hochschmieden/Resonanz-Schliff auf Herzstein & Sternstein, Verknüpfung mit Sonnenquarz/Prismensplittern und Ruinen-Resonanz) sowie **neue Stab-Archetypen** (z. B. Prismen-/Quarzstäbe mit eigenen Stabwerten, Mehrfach-Verstärkern oder Resonanz-Überladung).
2. **Zentraler Hauptort & Quests:**
   Ein großes Ruinen-Herzstück im Norden (z. B. großer Quarz-Tempel, Sonnenturm oder versunkene Sternwarte) samt Questreihe wird entworfen, sobald Landschaft, Boden, Quarzfelder und Höhenstufen im Spiel begehbar stehen.

---

## 11. Bauplan in klaren Stufen (Reihenfolge der Umsetzung)

Genau wie beim Hexenwald bauen wir die Wüste Schicht für Schicht auf, sodass jede Stufe sofort im Spiel betretbar, optisch prüfbar und mit automatisierten Tests abgesichert ist:

| Stufe | Fokus | Konkreter Inhalt & Dateien |
|---|---|---|
| **Stufe 1 (Start jetzt!)** | **Land, Übergang, Sand- & Quarztexturen** | • `tools/bake_desert_map.py`: Überregion 6 + Regionen 32–34 im Norden (`~85k` Tiles), Küsten-SDF, flaches Basis-Relief (Biom-Byte `206`), Altland 100 % byte-gleich.<br>• `BiomeBlend`: zweiter Kanal `g_arid` (`fade: 96` Tiles + Windzungen).<br>• `ground_tone.gdshader` & Bodenkacheln: 3-Phasen-Übergang (`STEPPE` → `SAND` mit Windriffeln → `QUARTZ`-Platten & Adern inkl. Tag-Glitzern & Nacht-Nachleuchten).<br>• `data/terrain.json`: Oberflächen `steppe`, `sand` (Spuren, Staub, `0.94x`), `quartz` (Klang/Funken, `1.04x`).<br>• Props-Sperre für Wiesenbewuchs + Weltkarte (`M`) mit Wüstenpalette & Symbolen + Entwickler-Teleport `IN DIE QUARZWÜSTE` + Tests (`test_desert_bake.py`, `tools/test_desert.tscn`). |
| **Stufe 2** | **Wüsten-Relief, Klippen, Oase & Karawanenweg** | • `tools/bake_desert_terrain.py`: Dünenmulden, Tafelberge (*Mesas*), Sandrampen & Quarz-Ruinentreppen.<br>• `relief.gdshader` Stil 6: geschichteter Sandstein mit leuchtenden Quarzadern.<br>• `lakes.json` Quarz-Oase + halb verwehte Quarz-Pflasterstraße (`ground.json`). |
| **Stufe 3** | **Klima, Mittagshitze & Magisches Wetter** | • Regensperre in der Wüste; Übersetzung in Sengende Sonne, Dünenwind, Resonanzwind & **Arkanes Quarzgewitter**.<br>• Status `sun_heat` (Ausdauerdruck am Tag, Abkühlung im Schatten / auf Quarz / an der Oase) + **Ellies Schweiß-Abwisch-Standgeste** (`art_hero3d.py`). |
| **Stufe 4** | **Wüstenflora, Quarz-Erze & Ruinenfragmente** | • `tools/art_desert.py`: Sonnenpalme, Glutdorn-Akazie, Glasaloe, Sternkaktus, Nacht-Wüstenrose, Sonnenquarz- & Prisma-Adern.<br>• Verstreute Lichtleit-Rinnen, gebrochene Quarz-Bögen und Resonanz-Obelisken. |
| **Stufe 5** | **Tierwelt der Wüste** | • Fennek, Quarz-Eidechsen, Wüstenbussard und Gold-Skarabäen. |
| **Stufe 6** | **Quarz- und Steinkolosse** | • Neue Gegnerfamilie (`Quarz-Koloss`, `Prismenwächter`, `Dünen-Skorpion`) inkl. Tag-Tarnung als Ruinensteine. |
| **Stufe 7** | **Hauptort, Zauberstab-Ausbau & Quests** | • Zentraler Ruinen-Hauptort, Überarbeitung des Zauberstab-Systems (neue Stabtypen & hohe Veredelung) und spätere Questreihen. |
