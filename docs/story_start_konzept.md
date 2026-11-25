# Story-Start in WINDKAP – drei Konzepte für das Startkonstrukt

> **Status: Konzept (2026-11-25).** Drei Vorschläge, wie das Spiel auf der Hauptmap (ALTMARK → Startzone `windkap`) offiziell beginnt, je mit einem großen Startkonstrukt.
> Pro Konzept gibt es zwei Google-Flow-Prompts: **(A) Key Art / Stimmung** und **(B) Spiel-Asset in 3/4-Draufsicht**. Das gewählte Bild wird danach in die Pixel-Pipeline (`tools/art_*.py`) umgearbeitet und in Windkap eingebaut.

## Ausgangslage

- **Storyboard:** Der Prolog (Varnholm, Blütennacht) endet in den **Kanälen der Steinsetzer** (Quest *FOLGE DEM WASSER*, Zeichen: Raute mit drei Strichen). Danach kommt Ellie verwundet ins Freie. Kapitel 1 (*Aus der Tiefe*) beginnt.
- **Windkap heute (`data/world/zones/windkap/zone.json`):** Küstenzone, „Wo der Bach ins weite Meer fällt“. Alter Name **KAP DER ALTEN WACHE**. Vorhanden: alter Leuchtturm + Steinsetzer-Kartentafel auf dem Kap (≈ 50,156), Kapkanzel-Aussicht, Silberbucht, Erlenbach mit alter Bogenbrücke, Wegstein *Wächterin der Bucht* (144,55), Startcamp (≈ 86,193).
- Das neue Konstrukt ersetzt den Kanaldeckel als **„zweite Geburt“** und ist der Moment, in dem Titel/Kapitelkarte erscheinen.

---

## Konzept 1 – DIE MÜNDUNG *(„Folge dem Wasser“)*

**Das Konstrukt:** Ein gewaltiges Steinsetzer-Wassertor, in die Steilklippe über der Silberbucht gehauen. Ein halbrunder Bogen, 4–5 Stockwerke hoch, flankiert von zwei kauernden Steinsetzer-Kolossen, die mit gesenkten Köpfen die Last des Bogens auf den Schultern tragen. Über dem Scheitel die riesige Raute mit drei Strichen, aus deren Rillen schwach türkises Leitstein-Licht sickert. Aus dem Tor stürzt das Kanalwasser in drei Kaskaden über Terrassen in die Bucht. Ein rostiges, halb heruntergelassenes Fallgitter, Muscheln und Seetang an den unteren Steinen, Möwennester in den Augenhöhlen der Kolosse. Bei Ebbe liegt eine Treppe aus nassen Quadern frei, die ins Innere führt.

**Story-Ablauf (≈ 6 Min.):**
1. Schwarzblende aus dem Prolog: *„Dann war über mir kein Eisen. Nur Rauschen.“* Ellie wird vom Kanalwasser durch das Fallgitter gespült, stürzt die Kaskaden hinab (kurze Fall-Kamerafahrt, keine Steuerung).
2. Sie wacht im Morgengrauen in einem Gezeitentümpel am Fuß der Mündung auf (Wasser 2.0 vorhanden: Strandpfützen, Brandung). Krümel sitzt auf ihrer Schulter. Blut im Wasser, Wunde an der Seite.
3. Erste Steuerung: Ellie kriecht ans Ufer → steht auf → **Kamerafahrt rückwärts** zeigt die ganze Mündung. Titel **SHADOWSPORE**, dann Kapitelkarte **KAPITEL 1 · AUS DER TIEFE**.
4. Erstes Ziel: die Klippe hinauf zum Leuchtturm (Kletter-Tutorial über `WallClimb`, Vault über Treibholz).
5. Hook: Hinter ihr schließt sich das Fallgitter knirschend von selbst. Wer hat es gezogen? (später: Orlen sucht sie in den Kanälen; das Gitter ist die erste Spur).

**Warum stark:** Nahtlose Fortsetzung des Prologs (*Folge dem Wasser* endet am Meer), nutzt Wasser 2.0 und Kletterei als Tutorial, das Konstrukt wird später zum Kanal-Dungeon-Eingang (Kapitel 2/6: zurück durch die Kanäle nach Varnholm).

---

## Konzept 2 – DAS STERNENAUGE *(„Ein Licht, das jemand für sie angelassen hat“)*

**Das Konstrukt:** Der alte Leuchtturm am Windkap ist in Wahrheit Caelias ältester Anker. Eine kolossale, verwitterte Statue der Wächterin, kniend auf dem Kap, 6–7 Stockwerke hoch, aus hellem Kalkstein mit goldenen Einlagen. Ihr Körper **ist** der Turm: Die Wendeltreppe läuft durch ihren Rumpf, ihre erhobenen, schalenförmigen Hände tragen statt eines Feuers eine gesprungene **Sternenlinse** (riesiger facettierter Kristall). Schwarze Leerenkristalle haben ihren Unterkörper und einen Arm überwuchert; ihr Gesicht ist halb abgebrochen, ein Auge blickt aufs Meer. Wind zerrt an steinernen Gewandfalten, Krähen sitzen auf ihren Schultern, Moos und Strandhafer am Sockel.

**Story-Ablauf (≈ 8 Min.):**
1. Ellie kriecht aus einem Kanalschacht in der Krypta unter der Statue (Innenraum über `Interiors`/`PocketSpace`). Dunkel, nur ein Lichtstrahl von oben durch die Linse. ✅ *umgesetzt: Krypta `sternenauge_krypta` + `CryptArrival`, siehe `sternenauge_flow_prompts.md` Nachtrag 4*
2. Die Wunde pulsiert violett; schwarze Fäden kriechen über den Boden auf sie zu (`ShadowPatch`). Ellie flieht die Wendeltreppe hinauf (kurze Verfolgung, Treppe bricht hinter ihr).
3. Oben, in den Händen der Statue: Die Linse ist dunkel. Ellie stolpert, ihre blutige Hand berührt den Kristall → **ein einzelner Strahl** zündet über das Meer. Die Stimme (noch namenlos, `DIE WÄCHTERIN`): *„…du bist es. Lauf. Ich halte sie, solange ich kann.“*
4. Titel **SHADOWSPORE** im Lichtstrahl, Kapitelkarte. Ellie klettert über den Arm der Statue ins Freie und sieht zum ersten Mal ALTMARK von oben (die Kapkanzel als Aussicht; Atlas schaltet frei, Kartentafel ist bereits dort).
5. Hook: Mit jeder späteren erweckten Statue wird die Linse heller. Im Finale leuchtet das Sternenauge über ganz ALTMARK.

**Warum stark:** Bindet Caelia von Minute 1 ein (erklärt, warum sie Ellie später rettet), macht den bestehenden Leuchtturm zum Herzstück, gibt dem Fortschritt ein sichtbares Weltsymbol (Linse = *Ankerlicht*, das fünfte Siegel).

---

## Konzept 3 – DIE ALTE WACHE *(„Kap der Alten Wache“)*

**Das Konstrukt:** Eine verlassene Seefestung des Ordens der Hohen Zinne, halb in die Klippe gestürzt. Zentrum ist ein **Torhaus** mit einem riesigen steinernen **Sonnenadler**, dessen ausgebreitete Schwingen das ganze Tor überspannen; ein Flügel ist abgebrochen und liegt zerschellt im Hof. Weinrote, zerfetzte Bannerreste flattern an den Zinnen, eine bronzene Alarmglocke (grün patiniert) hängt schief im Glockenstuhl über dem Tor. Die Seeseite ist eingebrochen, die Festung hängt mit einer Ecke über dem Abgrund, Wellen schlagen gegen die Fundamente. Im Hof eine geborstene Steinsetzer-Kanalöffnung, aus der Wasser sickert. Überall Spuren eines alten Kampfes: zerbrochene Schilde, schwarze Sporenflecken an den Wänden, eingetrocknet.

**Story-Ablauf (≈ 7 Min.):**
1. Ellie stemmt sich aus der Kanalöffnung im Hof der Festung. Nacht, Sturm, Regen (`WeatherManager`-Front).
2. Kurze Erkundung durch die Ruine (Schleich-Tutorial, `sneak`): Sie findet **Ser Bram**, den toten Kurier im weinroten Mantel, und sein Schwert → erstes Schwert (bestehender `FallenKnight`-Moment wandert hierher).
3. Schattenspinnen wachsen aus den Wänden (`ShadowBirth`). Ellie flieht auf den Wehrgang, sitzt in der Falle unter der Glocke.
4. **Umkehrpunkt:** Sie schlägt mit dem Schwert gegen die Glocke. Der Ton rollt übers Kap. Weit drüben am Leuchtturm geht eine Laterne an: Valdric hat es gehört. Titel **SHADOWSPORE**, Kapitelkarte.
5. Der Hinterhalt/die Rettung findet am Torhaus unter dem Sonnenadler statt; Valdric bleibt kurz vor dem Adler stehen, als würde er ihn kennen. Er geht nie durch dieses Tor.
6. Hook: Die Alte Wache war Valdrics Posten vor dem Großen Riss. Spätere Quest (Kap. 4, nach Hallgrat): Valdric kehrt zurück, läutet die Glocke selbst und hängt einen neuen Mantel an die Zinne.

**Warum stark:** Gibt dem alten Zonennamen eine Geschichte, verbindet Ellie und Valdric vom ersten Ton an, nutzt Wetter/Nacht/Sneak/Schattengeburt und den bereits gebauten Ritter-Moment.

---

## Entscheidung

**Gewählt: Konzept 2 – DAS STERNENAUGE.** Volles Prompt-Set: [sternenauge_flow_prompts.md](sternenauge_flow_prompts.md).

### Ursprüngliche Empfehlung

**Konzept 2 (Sternenauge)** ist das stärkste *Bild* und erzählt das meiste über die Welt. **Konzept 1** ist die sauberste Fortsetzung des Prologs. **Konzept 3** ist die emotionalste Figurenszene. Kombinierbar: Mündung (Ankunft) → Klettern zum Sternenauge (Titelmoment). Für das Startkonstrukt würde ich trotzdem **ein** Bild wählen.

---

## Google-Flow-Prompts

**Hinweise zur Nutzung**
- Prompts sind auf Englisch (liefert in Flow / Imagen / Nano Banana die präziseren Ergebnisse).
- Pro Konzept zuerst **A (Key Art)** zum Entscheiden, dann **B (Asset)** als Vorlage für die Umarbeitung. B ist das Bild, das du mir schicken solltest.
- Seitenverhältnis: A in **16:9**, B in **1:1** oder 4:3.
- Wenn Flow zu „glatt“/3D wird: den Satz *„strict limited-palette pixel art, visible square pixels, no anti-aliasing, no gradients“* am Ende wiederholen.
- Größe im Spiel (Orientierung für mich, nicht für Flow): ca. 18–24 × 14–20 Tiles (≈ 300–380 px breit), Spielerin ≈ 16 × 32 px.

### Gemeinsamer Stil-Block (in jeden Prompt bereits eingebaut)
> 16-bit era pixel art for a dark-atmospheric fantasy action RPG, mystical, calm and melancholic mood. Restrained low-saturation palette: black-violet as the base color of the world, cool blue-green grass, weathered pale stone, with turquoise and soft gold as the only accents. Light comes from the top left; every material has 3–4 tones from dark to light and a 1-pixel outline in a darker tinted version of its own color, never pure black. Crisp visible pixels, no anti-aliasing, no blur, no photorealism, no 3D render look.

---

### Konzept 1 – DIE MÜNDUNG

**1A – Key Art (16:9)**
```
A colossal ancient stone water gate carved into a towering sea cliff above a silver-grey bay at dawn. The gate is a huge semicircular arch, five stories tall, flanked by two kneeling giant stone guardians with bowed hooded heads, carrying the weight of the arch on their shoulders like Atlas figures. Above the keystone a giant carved rhombus symbol with three parallel lines, its grooves glowing faintly turquoise as if light is seeping out of the stone. From the dark mouth of the gate, water pours out in three wide cascading waterfalls over stepped stone terraces into the bay, throwing mist into the cold morning light. A rusted iron portcullis hangs half-lowered and bent inside the arch. Barnacles, mussels and dark green seaweed cling to the lower blocks, seagull nests sit in the empty eye sockets of the guardians, salt crust and moss on the ledges. At the bottom, among tide pools and wet black rocks, a tiny lone figure of a young woman with long loose silver-white hair in a dark servant dress lies half in the water, a small black crow standing on her shoulder, a faint violet glow at her side. The scale must feel enormous and ancient, a forgotten work of a vanished guild of stonemasons.
Camera: wide cinematic shot from slightly above, looking at the cliff face.
Style: 16-bit era pixel art for a dark-atmospheric fantasy action RPG, mystical, calm and melancholic mood. Restrained low-saturation palette: black-violet base tones, cool blue-green grass on the cliff top, weathered pale grey stone, silver sea, with turquoise and soft gold as the only accents. Light from the top left, soft pink-gold dawn sky. Every material 3–4 tones with a 1-pixel darker tinted outline, never pure black. Crisp visible square pixels, no anti-aliasing, no blur, no photorealism, no 3D render look, no text, no logo, no UI.
```

**1B – Spiel-Asset (1:1)**
```
Game asset for a 2D top-down pixel art RPG: a single large ancient stone water gate built into a short cliff wall, shown in classic 3/4 top-down orthographic view (camera about 45 degrees from above, front face and top surfaces both visible, no perspective distortion, like the buildings in a 16-bit action RPG). A semicircular stone arch, flanked by two kneeling hooded stone guardian statues carrying the arch on their shoulders. A carved rhombus symbol with three parallel lines above the keystone, grooves glowing turquoise. A half-lowered rusted iron portcullis inside the dark archway. Water flows out of the gate down three stepped stone terraces into a shallow pool at the bottom edge of the image. Barnacles, seaweed and moss on the lower stones, a few small seagulls perched on the statues. The cliff top above has a thin strip of cool blue-green grass. The whole structure is centered, complete and fully visible, with clean edges, standing on a plain flat dark neutral background (#1a1626), no landscape around it, no characters.
Style: strict limited-palette pixel art, 16-bit era, light from the top left, every material 3–4 tones, 1-pixel outline in a darker tinted shade of the neighboring color, never pure black. Palette: weathered pale grey and blue-grey stone, black-violet shadows, turquoise glow, soft gold highlights, desaturated sea green water. Visible square pixels, no anti-aliasing, no gradients, no blur, no 3D render, no text.
```

---

### Konzept 2 – DAS STERNENAUGE

**2A – Key Art (16:9)**
```
On a windswept grassy headland above a dark sea stands a colossal weathered stone statue of a kneeling goddess, seven stories tall, which is also an ancient lighthouse. She is carved from pale limestone with thin inlaid lines of tarnished gold, her long robes and veil whipped sideways by a frozen stone wind. Her head is bowed, half of her face has broken away, one serene eye still looks out over the ocean. Her two hands are raised together above her head like a cradle, and in them rests a huge cracked faceted crystal lens. A single clean beam of white-turquoise starlight shoots from the lens across the night sea toward the horizon. Small arched windows spiral up through her body where a hidden stair winds inside. Jagged black-violet void crystals have overgrown her lower body, one arm and the base, glowing with faint magenta veins, like an infection being held back by the light. Crows sit on her shoulders. Moss, sea thrift and beach grass at the stone base, waves crashing against black rocks below. On the balcony at her hands, a tiny figure of a young woman with long loose silver-white hair in a dark dress, one hand pressed against the crystal, the other holding her wounded side. Night sky full of stars with a faint violet seam on the eastern horizon.
Camera: wide cinematic shot from below and slightly to the side, emphasizing enormous scale.
Style: 16-bit era pixel art for a dark-atmospheric fantasy action RPG, mystical, calm, sacred and melancholic. Restrained low-saturation palette: black-violet night, cool blue-green grass, pale stone, with turquoise and soft gold as the only accents, magenta only in the void crystal veins. Every material 3–4 tones with a 1-pixel darker tinted outline, never pure black. Crisp visible square pixels, no anti-aliasing, no blur, no photorealism, no 3D render look, no text, no logo, no UI.
```

**2B – Spiel-Asset (1:1)**
```
Game asset for a 2D top-down pixel art RPG: a giant kneeling stone goddess statue that serves as a lighthouse, shown in classic 3/4 top-down orthographic view (camera about 45 degrees from above, front and top surfaces visible, no perspective distortion, like a landmark building in a 16-bit action RPG). Pale weathered limestone with thin gold inlay lines, flowing robes and veil, head bowed, half of the face broken off. Her raised cupped hands above her head hold a large faceted crystal lens (dim, pale turquoise, with a visible crack). A small stone balcony ring around the lens. Small arched windows spiraling up her body. A round stone base with an arched doorway at the front and a few stone steps. Jagged black crystals with faint violet and magenta veins overgrow her lower robe and one forearm. Two crows on her shoulders, moss and tufts of cool blue-green beach grass around the base. The whole statue is centered, complete and fully visible with clean edges, standing on a plain flat dark neutral background (#1a1626), no landscape, no sky, no characters, no light beam.
Style: strict limited-palette pixel art, 16-bit era, light from the top left, every material 3–4 tones, 1-pixel outline in a darker tinted shade of the neighboring color, never pure black. Palette: pale warm-grey stone, tarnished soft gold, black-violet shadows, turquoise crystal, magenta only in the void veins. Visible square pixels, no anti-aliasing, no gradients, no blur, no 3D render, no text.
```

---

### Konzept 3 – DIE ALTE WACHE

**3A – Key Art (16:9)**
```
A ruined medieval sea fortress of a fallen knightly order on a stormy cliff at night, half of it collapsed into the sea. At its center a massive gatehouse crowned by a gigantic carved stone sun-eagle whose outspread wings span the entire gate; one wing has broken off and lies shattered in the courtyard below. Tattered wine-red banners with a faded golden sun-eagle emblem whip in the storm from the battlements. A large green-patinated bronze alarm bell hangs crookedly in a wooden belfry above the gate. The seaward wall has caved in, one corner of the fortress hangs over the abyss, huge waves crash against the foundations. In the courtyard a broken stone canal opening with water seeping out, broken shields, a fallen knight in a wine-red cloak slumped against a wall, dried black creeping stains on the stones like old mold. Heavy rain, a flash of lightning illuminating the eagle. On the wall walk, a tiny figure of a young woman with long loose silver-white hair in a dark dress, swinging a sword against the bell, sound rings visible as faint arcs. Far away on the next headland, a single warm lantern light.
Camera: wide cinematic shot, slightly from above, the eagle gate as the focal point.
Style: 16-bit era pixel art for a dark-atmospheric fantasy action RPG, mystical, heavy and melancholic mood. Restrained low-saturation palette: black-violet night, cold blue-grey stone, deep wine-red banners, with turquoise lightning highlights and soft gold as the only accents. Every material 3–4 tones with a 1-pixel darker tinted outline, never pure black. Crisp visible square pixels, no anti-aliasing, no blur, no photorealism, no 3D render look, no text, no logo, no UI.
```

**3B – Spiel-Asset (1:1)**
```
Game asset for a 2D top-down pixel art RPG: the ruined gatehouse of a medieval knight fortress, shown in classic 3/4 top-down orthographic view (camera about 45 degrees from above, front facade and top of the walls visible, no perspective distortion, like a castle building in a 16-bit action RPG). Two squat stone towers flank a large arched gate. Above the gate a huge carved stone sun-eagle with outspread wings spanning the width of the gatehouse, its right wing broken off at the shoulder. A wooden belfry on top holding a crooked green-patinated bronze bell. Torn wine-red banners with a faded golden eagle hanging from the battlements. Cracked and partly crumbled walls, rubble at the base, moss in the joints, a few dried black stains creeping on the stones. A short section of ruined wall on each side ending in rubble. The structure is centered, complete and fully visible with clean edges, standing on a plain flat dark neutral background (#1a1626), no landscape, no sea, no characters, no weather.
Style: strict limited-palette pixel art, 16-bit era, light from the top left, every material 3–4 tones, 1-pixel outline in a darker tinted shade of the neighboring color, never pure black. Palette: cold blue-grey stone, black-violet shadows, deep wine-red cloth, patinated bronze green, soft gold accents. Visible square pixels, no anti-aliasing, no gradients, no blur, no 3D render, no text.
```

---

## Nach der Auswahl (Umarbeitung & Einbau)

1. Bild B herunterskalieren und auf Projektpalette quantisieren, Kanten/Outlines nach `design_guide.md` nachziehen → deterministischer Generator `tools/art_<konstrukt>.py` mit Rohbild in `tools/art_sources/`.
2. Aufteilen in Ebenen: Boden/Sockel (unter Spieler), Körper (y-sortiert, Pivot unten-Mitte), Glow-Layer (`Unlit.material()`: Rune/Linse/Fenster), ggf. Wasser-/Lichtstrahl-Effekt.
3. Kollision + begehbare Bereiche, Eintrag in `data/world/zones/windkap/zone.json` (`landmarks`, `spawn`), Story-Szene als eigenes Skript neben `IntroScene`.
4. Prüfung: `py -3 tools/check_zone.py windkap`, Headless-Compile, Preview-Szene.
