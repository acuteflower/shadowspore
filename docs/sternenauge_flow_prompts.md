# DAS STERNENAUGE – Google-Flow-Prompts (Startkonstrukt WINDKAP)

> **Status: Prompt-Set (2026-11-25).** Gewählt aus [story_start_konzept.md](story_start_konzept.md), Konzept 2.
> Grundlage für Aussehen: Caelia ([goettin_konzept.md](goettin_konzept.md), [caelia_interstellar_konzept.md](caelia_interstellar_konzept.md)), Wegstein-Statuen ([waystones.md](waystones.md)), Ellie ([characters/ellie.md](characters/ellie.md)), Stil ([design_guide.md](design_guide.md)).

## Was das Sternenauge ist (Kurzfassung fürs Design)

Caelias **ältester Anker** und Urbild aller Wegstein-Statuen: eine kolossale **kniende Wächterin** aus blassem Violettstein auf der Spitze des Windkaps. Ihr Körper **ist** der Leuchtturm: Eine Wendeltreppe läuft durch den Rumpf, kleine Bogenfenster folgen ihr spiralförmig nach oben. Mit beiden Händen hebt sie über ihren Kopf eine **facettierte Sternenlinse** (statt eines Leuchtfeuers). Hinter ihrem Haupt ein zerbrochener **goldener Heiligenschein mit Strahlenkranz aus Kristallen** (wie bei allen Wegsteinen). Schwarze **Leerenkristalle** mit violett-magenta Adern haben Sockel, Unterkörper und den linken Unterarm überwuchert. Im Sockel ein Bogentor zur **Krypta**, in der Ellie aus dem Kanalschacht kriecht.

Zwei Zustände wie bei den Wegsteinen: **WILD/SCHLAFEND** (Spielbeginn, Linse dunkel, Risse, Moos) und **ERWACHT** (Linse brennt, Augen türkis, Gold poliert, Kristalle leuchtend). Spätere Zwischenstufen (Linse wird mit jeder Statue heller) mache ich in der Pipeline.

## Design-Bibel (in alle Prompts eingearbeitet)

| Element | Festlegung |
|---|---|
| **Haltung** | Kniet auf dem rechten Knie, linkes Knie aufgestellt, Rücken leicht gebeugt, Kopf zur Linse/zum Meer geneigt, beide Arme über dem Kopf, Hände wie eine Schale. Ruhig, tragend, nicht triumphierend. |
| **Gesicht** | Groß, ruhig, alt-würdevoll, jung wirkend. Geschlossene Augen unter feinen Brauen (wild); erwacht leuchten sie mond-türkis (`#d0fff8`). Ein feiner Riss läuft über Stirn und Wange, ein Stück der Wange ist abgeplatzt. |
| **Haar** | Lang, in schweren steinernen Wellen und zwei langen Zöpfen über Schultern und Rücken; Spitzen laufen in feine Sternenpunkte aus (Einlagen aus Gold-/Türkisstein). |
| **Schleier** | Dünner, nach hinten wehender Steinschleier vom Hinterkopf, im Wind erstarrt. |
| **Gewand** | Asymmetrisch drapiert, kein Korsett, fließend; am Saum zerfließend in Stoffbahnen, die in den Sockel übergehen. Säume und Adern als **türkise und goldene Einlagelinien** (Umkehrung der Leeren-Adern). Eine Stola/Schärpe mit eingemeißelten **Sternbild-Linien** weht vom erhobenen Arm. |
| **Schmuck** | Goldene Reifen an Handgelenken und Knöcheln (barfuß), kleine goldene **Kintsugi-Lichtnarbe** an der linken Schulter. |
| **Heiligenschein** | Großer goldener Ring hinter dem Kopf mit Strahlenkranz aus facettierten Kristallen; wild: Ring gebrochen, drei Kristalle fehlen. |
| **Linse** | Facettierter, leicht bläulich-klarer Kristall, ca. so groß wie ihr Kopf ×2, in goldener Fassung; ein diagonaler Sprung. Schmaler Steinbalkon (Laternenring mit Geländer) um die Hände. |
| **Material** | Blasser, leicht violetter Kalkstein (lavendelgrau), Gold angelaufen (wild) / poliert (erwacht). |
| **Leere** | Gezackte, fast schwarze Kristalle (`#07040d`–`#221740`), violette Adern, magenta Kerne, wachsen von unten rechts am Sockel hoch über Knie und Unterkörper und um den linken Unterarm. |
| **Natur** | Moos in Fugen, Strandhafer, Grasnelken, ein Krähennest auf der Schulter, zwei Krähen. Salzkrusten. |
| **Sockel** | Runder gestufter Felssockel mit Bogentor (Krypta) vorne, Steinsetzer-Raute mit drei Strichen über dem Tor, ein paar Stufen. |
| **Licht** | Immer von links oben. Erwacht: Linse, Augen, Einlagen, Halo leuchten (später eigene Unlit-Ebene). |

**Ellie (falls im Bild):** 19, schlank, **langes silberweißes Haar mit Lavendelschatten**, offen, kleine goldene Haarnadel; Choker mit kleinem violettem Kristall. Im Story-Start trägt sie noch das **dunkle Dienerinnenkleid mit heller Schürze**, verdreckt und nass, rechte Hand an der blutenden linken Taille, schwacher violetter Schimmer an der Wunde. **Krümel:** kleine schwarze Krähe, oft auf ihrer Schulter.

---

## Tipps für Flow

- **Reihenfolge:** Zuerst **P2 (Asset wild)** so lange generieren, bis Silhouette und Haltung sitzen. Dieses Bild dann in Flow als **Ingredient/Referenzbild** für P3, P4 und P1 verwenden, damit die Statue überall gleich aussieht.
- Seitenverhältnisse: P1/P5/P6 **16:9**, P2/P3 **1:1** (oder 3:4 hoch, wenn die Statue zu gedrungen wird), P4 **16:9**.
- Wird es zu glatt oder 3D: den Schlusssatz *„strict limited-palette pixel art, visible square pixels, no anti-aliasing, no gradients“* noch einmal anhängen.
- Wird die Statue stehend statt kniend: *„she is KNEELING on one knee, not standing“* an den Anfang setzen.
- **Für den Einbau brauche ich vor allem P2 + P3** (gleiche Pose, beide Zustände). P4 ist Detailreferenz, P5 die Krypta, P1/P6 sind Stimmung und Intro-Vorlage.

---

## P1 – Key Art: Der erste Strahl (16:9)

```
Epic key art for a dark-atmospheric fantasy pixel art RPG. On the windswept grassy tip of a high sea cape stands a colossal ancient statue of a goddess that is also a lighthouse, about seven stories tall. She KNEELS on her right knee with her left knee raised, back slightly bent, head gently bowed. Both arms are lifted above her head, hands cupped together like a bowl, and in them rests a huge faceted crystal lens in a gold setting, ringed by a narrow stone lantern balcony with a railing. From the lens a single clean, sharp beam of white-turquoise starlight shoots out over the night sea to the horizon, the first light in centuries.
The goddess is carved from pale, slightly violet limestone with lavender-grey shading. Her face is large, serene, ancient yet youthful; a fine crack runs across her brow and cheek and a piece of her cheek has chipped away. Her eyes are just opening and glow a soft moon-turquoise. Long heavy stone hair in waves and two long braids falls over her shoulders, the tips ending in tiny inlaid star points. A thin stone veil flows back from her head, frozen in the wind. Her asymmetric draped robe has no corset and dissolves at the hem into flowing stone bands that merge into the rock base; its seams and veins are inlaid with glowing turquoise and gold lines. A stole carved with constellation lines streams from one raised arm. Gold bands on wrists and bare ankles, a small golden kintsugi scar of light on her left shoulder. Behind her head a large broken golden halo with a crown of faceted crystal rays, three of them missing.
Jagged, almost black void crystals with violet veins and magenta cores have overgrown the base, her lower body, her knee and her left forearm, like an infection held back by the light. Small arched windows spiral upward through her body where a hidden staircase winds inside. At the round stepped rock base an arched doorway leads into a crypt, a carved rhombus with three lines above it. Moss in the joints, beach grass and sea thrift around the base, a crow's nest on her shoulder, two crows. Waves crash against black rocks below the cliff.
On the lantern balcony beside the lens, very small: a 19-year-old young woman with long loose silver-white hair with lavender shadows, in a soaked, dirty dark servant dress with a pale apron, a choker with a small violet crystal; her bloody left hand pressed against the lens, her right hand holding her wounded side, which glows faintly violet. A small black crow sits on her shoulder.
Night sky full of stars, a faint violet seam of corruption on the eastern horizon, cold wind, sea spray catching the beam.
Camera: wide cinematic low angle from the cliff path below, the statue filling two thirds of the height, emphasizing immense scale and stillness.
Style: 16-bit era pixel art, mystical, sacred, calm and melancholic. Restrained low-saturation palette: black-violet night as the base color, cool blue-green grass, pale lavender-grey stone, turquoise and soft gold as the only accents, magenta only inside the void crystals. Light from the top left plus the lens beam. Every material 3–4 tones from dark to light with a 1-pixel outline in a darker tinted version of its own color, never pure black. Crisp visible square pixels, no anti-aliasing, no blur, no photorealism, no 3D render look, no text, no logo, no UI.
```

## P2 – Spiel-Asset: Sternenauge WILD / schlafend (1:1) ⭐ wichtigstes Bild

```
Game asset for a 2D top-down pixel art action RPG: a single colossal kneeling goddess statue that is also a lighthouse, shown in classic 3/4 top-down orthographic view (camera about 45 degrees from above, front and top surfaces both visible, no perspective distortion, like a landmark building in a 16-bit action RPG). The statue is fully visible, centered, with clean edges, on a plain flat dark neutral background (#1a1626). No landscape, no sky, no sea, no characters, no light beam.
State: DORMANT and overgrown, asleep for centuries.
Pose: she KNEELS on her right knee with her left knee raised, back slightly bent, head bowed toward the viewer. Both arms raised above her head, hands cupped together holding a large faceted crystal lens (dull, dark, cloudy blue-grey, unlit, with one diagonal crack) in a tarnished gold setting, surrounded by a narrow round stone balcony with a small railing.
Body and face: pale, slightly violet limestone with lavender-grey shading. Large calm face with closed eyes under fine brows, a crack across brow and cheek, a chipped cheek. Long heavy stone hair in waves and two long braids over the shoulders. A thin stone veil flowing backward. Asymmetric draped robe without corset, hem dissolving into stone bands that flow into the base, with tarnished dull gold and dull teal inlaid seam lines. A stole with carved constellation lines from one raised arm. Tarnished gold bands on wrists and bare ankles. Behind her head a large broken tarnished golden halo with a crown of faceted crystal rays, ring cracked, three rays missing.
Decay: jagged almost-black void crystals with faint violet veins and dim magenta cores grow from the lower right of the base over her knee, lower robe and around her left forearm. Moss and ivy in the joints, salt crust, tufts of cool blue-green beach grass and pink sea thrift around the base, a crow's nest with two black crows on her left shoulder. Small dark arched windows spiral up through her body.
Base: round stepped rock plinth, at the front a dark arched crypt doorway with a few worn steps, a carved rhombus with three parallel lines above the arch.
Proportions: tall and monumental, the statue about 1.6 times as tall as it is wide, the lens at the very top.
Style: strict limited-palette pixel art, 16-bit era, light from the top left, every material 3–4 tones from dark to light, 1-pixel outline in a darker tinted shade of the neighboring color, never pure black. Palette: pale lavender-grey stone, tarnished dark gold, black-violet shadows, dull teal inlays, black void crystals with violet and dim magenta. Visible square pixels, no anti-aliasing, no gradients, no blur, no 3D render, no text.
```

## P3 – Spiel-Asset: Sternenauge ERWACHT (1:1) – mit P2 als Referenz

```
Using the reference image as the exact same statue in the exact same pose, camera angle, size, framing and plain dark background (#1a1626): show the colossal kneeling goddess lighthouse statue AWAKENED and restored, in classic 3/4 top-down orthographic pixel art view.
Changes from the dormant version: all cracks healed, the chipped cheek whole again, the halo ring complete with all crystal rays restored and glowing softly gold and turquoise. Moss, ivy and salt crust gone; only a little fresh beach grass and sea thrift remain at the base. The gold on bands, halo and lens setting is polished and warm (#e6c468). The inlaid seam lines of robe and stole glow turquoise (#78f4e6) and gold, the constellation lines on the stole shine like small stars. Her eyes are open and glow a calm moon-turquoise (#d0fff8). The crystal lens in her raised hands is clear, bright and blazing with white-turquoise starlight, its crack sealed with a golden kintsugi line. The small arched windows spiraling up her body glow warm. The void crystals are gone; where they were, small clean pale crystals with a turquoise core remain. The crypt doorway glows faintly from within, the rhombus with three lines above it shines turquoise. The two crows still sit on her shoulder. No light beam, no characters, no landscape.
Style: strict limited-palette pixel art, 16-bit era, light from the top left, every material 3–4 tones, 1-pixel outline in a darker tinted shade of the neighboring color, never pure black. Palette: pale lavender-grey stone, polished gold, turquoise light, black-violet shadows. Visible square pixels, no anti-aliasing, no gradients, no blur, no 3D render, no text.
```

## P4 – Design-Sheet: Ansichten & Details (16:9) – mit P2 als Referenz

```
Character and prop design reference sheet in pixel art for the same colossal kneeling goddess lighthouse statue as in the reference image, dormant overgrown state, on a plain flat dark neutral background (#1a1626), neatly arranged with generous spacing, no text labels.
Top row, full statue in three orthographic views at equal scale: front view, left side view, back view (showing the long braids, the flowing stone veil, the back of the broken halo, the spiral of small windows and a small back entrance at the base).
Bottom row, close-up details at larger scale: (1) the head and face with closed eyes, the crack across brow and cheek, the chipped cheek and the veil; (2) the cupped hands with the faceted crystal lens in its gold setting and the round stone balcony with railing; (3) a section of the broken golden halo with faceted crystal rays; (4) a cluster of black void crystals with violet veins and magenta cores growing over her knee and robe; (5) the crypt doorway in the base with the carved rhombus with three lines; (6) a strip of robe hem with inlaid turquoise and gold seam lines and constellation carvings.
Style: 16-bit era pixel art, consistent with the reference, light from the top left, every material 3–4 tones, 1-pixel outline in a darker tinted shade, never pure black. Palette: pale lavender-grey stone, tarnished gold, dull teal inlays, black-violet shadows, magenta only in void crystals. Visible square pixels, no anti-aliasing, no gradients, no blur, no 3D render, no text, no labels.
```

## P5 – Die Krypta unter dem Sternenauge (16:9, Innenraum)

```
Interior scene for a 2D top-down pixel art action RPG in classic 3/4 top-down view (camera about 45 degrees from above, back wall visible, no perspective distortion): a circular ancient crypt beneath a giant goddess statue on a sea cape, the very first room of the game.
In the middle of the floor an open square stone canal shaft with dark water, an iron grate pushed aside, wet handprints and drag marks leading away from it, a thin trail of blood drops. The round walls are built of pale lavender-grey limestone blocks, carved with rhombus symbols with three lines and faded turquoise inlay. Along the wall a spiral stone staircase rises up into darkness. On the back wall a weathered relief of the kneeling goddess holding a lens above her head, half covered by black void crystals with faint violet veins and dim magenta cores. Black creeping stains with violet threads crawl slowly from the shaft across the floor and up the walls. From a round opening high in the ceiling a single narrow column of cold turquoise-white light falls onto the floor, dust motes floating in it. Puddles, broken urns, old offering bowls with dried flowers, roots hanging from the ceiling, a few small glowing moss patches in turquoise.
The room is empty of characters.
Mood: dark, quiet, sacred, threatening, the light column the only safe spot.
Style: 16-bit era pixel art, restrained low-saturation palette with black-violet as base, pale lavender-grey stone, turquoise and soft gold accents, magenta only in void crystals. Light from the top left plus the ceiling light column. Every material 3–4 tones with a 1-pixel darker tinted outline, never pure black. Visible square pixels, no anti-aliasing, no gradients, no blur, no 3D render look, no text, no UI.
```

## P6 – Intro-Keyframe: Ellie an der Linse (16:9, Nahaufnahme)

```
Close-up cinematic keyframe in pixel art for a dark-atmospheric fantasy RPG intro. Night, on a narrow stone lantern balcony at the top of a colossal goddess statue above the sea. Filling the right half of the frame: the goddess's enormous cupped stone hands of pale lavender-grey limestone with gold wrist bands, holding a huge faceted crystal lens in a tarnished gold setting, with a diagonal crack. The left side of her stone face is visible above, eyes closed, a crack across the cheek, the edge of a broken golden halo with crystal rays behind it.
In the left half: Ellie, a slender 19-year-old young woman with long loose silver-white hair with lavender shadows blowing in the wind, a small golden hairpin, a choker with a small violet crystal, wearing a soaked, torn, dirty dark servant dress with a pale apron. Exhausted, kneeling, her right hand pressed to her left waist where blood seeps and a faint violet glow pulses under her fingers. Her bloody left hand touches the lens. At the point of contact, white-turquoise light bursts into the crystal, spreading through its facets and the crack; first rays break out of the lens. A small black crow on her shoulder spreads its wings in surprise. Her face is lit from below by the turquoise light, eyes wide, a mix of fear and awe.
Behind: starry night sky, black sea far below, a faint violet seam on the horizon.
Style: 16-bit era pixel art, high detail but crisp pixels, restrained low-saturation palette: black-violet night, pale stone, turquoise and soft gold as accents, violet only at the wound. Every material 3–4 tones with a 1-pixel darker tinted outline, never pure black. No anti-aliasing, no blur, no photorealism, no 3D render look, no text, no UI.
```

## P7 – Optional: Video in Flow (Veo), aus P1 oder P6 als Startbild

```
Animate this pixel art scene, keeping the exact pixel art style, palette and composition. The young woman's hand rests on the crystal lens; after one second the light inside the crystal grows from her fingertips, flows through the facets and seals the crack with a golden line. The statue's closed stone eyes slowly open and glow turquoise. With a soft pulse, a sharp beam of white-turquoise starlight shoots out of the lens across the night sea to the horizon. The broken golden halo behind the statue's head flickers and three missing crystal rays briefly appear as light. The crow takes off from her shoulder and circles once through the beam. Her silver-white hair and the sea spray move in the wind. Slow, calm, sacred pacing, camera slowly pulling back and upward. No camera shake, no style change, no smooth 3D look, no text.
```

---

## Umsetzung (2026-11-25) ✅

- **Vorlagen:** P2 (wild), P3 (erwacht), P4, P1, P5 liegen unter `tools/art_sources/sternenauge/flow_*.webp`.
- **Pipeline:** `py -3 tools/art_sternenauge.py` tastet die entrauschten Vorlagen im Raster `PITCH` 2,875 ab (größer als das ~4-px-Pseudoraster), stellt frei (Randflutung + Rettung der fast schwarzen Leerenkristalle + kleine Löcher/Kryptatür deckend), bildet den Stein auf die Kalkstein-Rampe von `rocky_ground.gdshader` ab (passt zum Felsplateau), Gold warm, Leere schwarzviolett, reduziert auf eine gemeinsame 72-Farben-Palette und baut je Zustand eine Leuchtebene. Ausgabe: `assets/props/sternenauge/sternenauge.png` + `_glow.png` (2 Frames à 212×379: wild | erwacht) und `data/sternenauge_art.json` (Linse, Bodenellipse, Tür).
- **Entity:** `Sternenauge` (`src/world/v2/sternenauge.gd`) ersetzt `WindkapProps.LighthouseRuin` in `ZoneStage._attach_ruin` (Knoten heißt weiter `WindkapLighthouse`, Gruppe `windkap_lighthouse` bleibt → Nachtschutz und Kartentafel funktionieren unverändert). Knoten = Mitte der Bodenellipse (y-Sortierung), elliptische Kollision 102×42 px, Treppe vor der Tür frei begehbar. Erwachen: 2,6-s-Überblendung, Funken an der Linse, Linsen- & Sockellicht, gedithertes Strahlenbündel (`sternenauge_beam.gdshader`) nach West-Südwest über das Meer, schwenkt langsam, nachts voll.
- **Landmarke:** `windkap_leuchtturm` heißt jetzt **DAS STERNENAUGE** (zone.json + `build_altmark_world.py`).
- **Test:** `Godot --headless --path . --fixed-fps 60 res://tools/test_sternenauge.tscn` (8 Prüfungen), mit Fenster `-- --capture-dir=...` für Bilder.
- **Noch offen (Story-Schritt):** Krypta-Innenraum nach P5, Kanalschacht-Ankunft, Wendeltreppe, Linsenszene mit Titelkarte; heute erwacht das Sternenauge noch über die Kartentafel.

### Nachtrag: Platz, Stelen, Aufräumen (2026-11-25)
- **Statue:** Flächenmittel-Abtastung (jedes Pixel = 1 Weltpixel, keine Doppelpixel), hintergrundfarbene Lücken werden transparent (nur Fenster, Kryptatür und die Fassung der Leerenkristalle bleiben dunkel), 1-px-Kontur in getönter Eigenfarbe.
- **Steinplatz:** `py -3 tools/art_sternenauge_plaza.py` → `plaza.png` (368×216, Keilstein-Ringe in der Felsboden-Rampe, Moosfugen, Flechten, Prozessionsachse zur Kryptatreppe, eingelegter Goldring mit 8 Türkis-Rauten, zwei abgestürzte Halo-Strahlen) über `GroundSurfaces.add_stone_plaza` (Steinschritte, kein Gras durch die Platten). Runenring leuchtet über `Sternenauge` (`plaza_glow.png`) mit dem Erwachen.
- **Runenstelen:** `SternenaugeStele` (3 Varianten, wild/erwacht), vier Stück auf dem Außenring, folgen `Sternenauge.awake_blend()`.
- **Freihaltezone:** `ZoneStage.in_sanctum()` hält Felsen, Felsdetails, Flora und Bäume vom Platz fern.
- **Entfernt:** `WindkapProps.LighthouseRuin`, `windkap_ruin.png` (+Glow), `tools/art_windkap_ruin.py`, die vier Begleit-Ruinen am Kap.

### Nachtrag 2: Platz neu, Pult & Kanzelbank (2026-11-25)
- **Steinplatz neu:** `tools/art_sternenauge_plaza.py` malt jetzt in der Sprache des Felsbodens: dieselben drei Gesteinsarten wie `rocky_ground.gdshader` (Kalkstein, Moos-Schiefer, Travertin; je Schatten/Mitte/Licht/Kante), Steine im Geröllmaßstab (12 Boden-px tief ≈ 7 px vorn, 12–21 px lang), 1-px-Lichtkante oben links, Schattenkante unten rechts, Fugen aus Lehm oder Polstermoos, **keine** Außenkontur. Innen warmer Travertin wie die Statue, außen Kalk/Schiefer; der Rand franst organisch ins Geröll aus (`_edge_r`, nach Süden weiter gepflastert). Prozessionsachse aus großen Platten, Runenring als 1-px-Goldfaden auf dunklem Schiefer-Bordstein mit 8 Türkis-Rauten. 424×244 px, gepflasterter Kern 171×96 (`plaza_paved_radii`) = Freihaltezone & Steinschritte; im ausgefransten Rand wachsen Gras und Flora wieder.
- **Shader-Fix:** `ground_prop_lit.gdshader` hat die Textur doppelt genommen (in Godot 4 ist `COLOR` im Fragment schon Textur × Modulate → Farben quadriert, dunkel/oliv). Neuer Schalter `texture_once`; der Platz nutzt ihn (eigene Materialkopie in `GroundSurfaces.add_stone_plaza`). Alte Boden-Props (Antikplatten, Hof, Waldboden) bleiben unverändert.
- **Steinsetzer-Pult:** `assets/props/map_tablet.png` (+Glow) kommt jetzt aus demselben Skript: Stufensockel aus Platzgestein, schräges Travertin-Pult mit Goldrahmen, ALTMARK auf Schiefer eingraviert (erwacht: Türkisküste, violetter Riss, goldenes Windkap). Alter Generator `tools/art_map_tablet.py` entfernt. Kollider 34×9.
- **Kanzelbank:** `VistaPoint` Variante 3 (`assets/props/sternenauge/vista_bench.png`), Kapkanzel nutzt sie (zone.json + `build_altmark_world.py`). Andere Aussichtspunkte bleiben unverändert.
- **Runenstelen** neu im selben Gestein (Deck-/Vorder-/Seitenfläche, Quaderfuge, Goldband).
- **Test:** 14 Prüfungen (u. a. Kanzelbank-Variante, Pult vorhanden), Bilder 09 (Pult) und 10 (Bank).

### Nachtrag 3: Platz wieder entfernt (2026-11-25)
- **Steinplatz entfernt** (Wunsch): kein Bodendecal mehr (`plaza.png`/`plaza_glow.png`, `GroundSurfaces.add_stone_plaza`, `texture_once` im Shader zurückgebaut). Die Statue steht direkt auf dem Felsboden des Kaps. Stelen, Steinsetzer-Pult und Kanzelbank bleiben (`tools/art_sternenauge_plaza.py` erzeugt nur noch diese).
- **Freihaltezone:** `ZoneStage.sanctum()` nutzt `sanctum_radii` (171×96) aus `data/sternenauge_plaza.json`: keine Felsen, Bäume, Büsche um Statue und Stelen.
- **Sockel grasfrei:** unsichtbarer Stein-Fußabdruck `GroundSurfaces.add_stone_footprint` (112×54) unter Sockel, Treppe und Kryptatür.
- **Statue:** Die dunklen Körper der Leerenkristalle werden nicht mehr freigestellt (`_clear_dark_gaps`: Komponenten im Kristallbereich bleiben deckend) → keine durchsichtigen Stellen mehr.
- **Test:** 15 Prüfungen (u. a. kein Platz-Decal, Treppe grasfrei).

### Nachtrag 4: Krypta & Ankunft durch den Kanalschacht (2026-11-25)
- **Krypta (Innenraum `sternenauge_krypta`):** `py -3 tools/art_sternenauge_crypt.py` tastet Flow-Bild P5 (`tools/art_sources/sternenauge/flow_crypt.webp`) 2:1 ab → `assets/interior/sternenauge_krypta/` (`crypt.png` 672×378, `front.png` Vordermauer, `crypt_glow.png` Lichtschacht/Kristalladern/Fries). 1 Pixel = 1 Weltpixel, Ellie passt durch den Treppenbogen. Layout, Kollision (Bodenellipse, Treppenblock, Schacht, Krüge), Lichter und Ausgang stehen in `data/interiors.json`.
- **Zugang:** `Sternenauge` legt am Fuß der Treppe eine `Doorway` an („KRYPTA BETRETEN“) und meldet sich als Eingang (`exit_position` vor der Treppe). Die Wendeltreppe oben links ist der Ausgang („HINAUFSTEIGEN“).
- **Ankunft (neues Spiel):** `ZoneWorld.start_intro()` setzt den lokalen Spieler in die Krypta und startet `CryptArrival` (`src/world/v2/crypt_arrival.gd`): drei Texttafeln auf Schwarz (*„Ich weiß nicht, wie lange ich gelaufen bin.“ / „Irgendwann bin ich nur noch gekrochen.“ / „Dann war über mir Stein. Und Licht.“*, E überspringt), dann Aufblende und die Kletterbilder aus `player_emerge.png` ab dem Griff an die Kante (Klopfen/Deckel entfallen, das Gitter liegt schon daneben). Sie steigt am Ostrand aus dem Schacht und kriecht über die gemalten Hand- und Schleifspuren (Anker Raum-px 366,263), keucht, hustet und steht auf. Danach `Player.end_wake` (HUD wächst ein, keine v1-Quest) und der Hinweis „STEIG DIE TREPPE HINAUF“.
- **Noch offen:** Schattenfäden-Verfolgung und einstürzende Treppe, Linsen-Szene mit Stimme und Titelkarte, Ausstieg über den Arm (Konzept 2, Schritte 2–4).
- **Test:** `tools/test_sternenauge.tscn`, 25 Prüfungen (Krypta betreten/verlassen, Schacht blockiert, Ankunft hält die Spielerin, gibt die Steuerung zurück, sie steht neben dem Schacht), Bilder 12–17.
