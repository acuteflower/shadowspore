# Higgsfield: Dialogporträt-Vorlagen

Ablauf: Sheet des Charakters (`docs/img/character_sheets/<id>.png`) als Bildreferenz hochladen, **MASTER-PROMPT** + **Charakterblock** einfügen, generieren, mir das Ergebnis geben. Ich rechne es auf 103×153, 30 Farben, Nearest Neighbor, harte Transparenz herunter (`tools/prepare_dialogue_portrait.gd`, Vorgaben `docs/dialogue_art.md`).
Higgsfield soll **kein** fertiges Pixelbild liefern, sondern eine saubere, hochauflösende Vorlage. Das Pixeln passiert bei mir.

Tipps: Referenz 1 = Sheet des Charakters (Identität). Referenz 2 (optional) = `assets/ui/sources/adventurer_dialogue_v2.png` oder Ellies Porträt (Ausschnitt/Maßstab). Mehrere Varianten erzeugen und die mit der besten Gesichtspartie wählen. Hintergrund bewusst einfarbig, damit ich freistellen kann.

---

## MASTER-PROMPT (englisch, direkt kopieren)

```
Character dialogue portrait, single character, stylized dark-fantasy painterly illustration with chunky, bold, clearly readable shapes (designed to be downsampled to 103x153 pixel art later). Use the attached sprite sheet as the exact identity reference: keep the character's hair, face, outfit, colors, accessories and proportions identical to the sprite in all eight views; use the back and side views to get the clothing details right.

FRAMING: head to hip, cut off at the hips. No knees, legs or feet. Eye-level camera, three-quarter view, the body and face turned toward the RIGHT of the image (the dialogue text sits to the right of the portrait). Head including hair/hat/helmet fills roughly 30% of the image height; head top at about 4% from the top edge, eyes at about 24%, chin at about 36%, shoulders at about 40-45%, bottom edge cuts at the hips. Shoulders and clothing fill 85-95% of the image width. Portrait format 2:3.

STYLE: simplified large color masses, hard edges, angular outlines, no soft airbrushing, no fine texture noise, no gradients; 3-4 flat tonal steps per material (shadow, mid, light, highlight); about 30 colors total. Light comes from the top left, cool violet fill from the right, so forms stay readable on a dark background. Dark plum-violet outline around the figure. Muted twilight palette (violet, teal, wine red, dusty greys, warm skin), small accents of gold or glowing teal only where the character has them.

EXPRESSION: calm, attentive, mouth closed or slightly relaxed (neutral resting face, so the mouth can be animated later). Eyes open and clearly drawn, looking toward the right/the viewer's text.

BACKGROUND: perfectly flat solid pure magenta #FF00FF, no gradient, no shadow on the ground, no vignette, no frame.

DO NOT: no text, no border, no UI, no full body, no legs, no photo-realism, no 3D render look, no motion blur, no blur, no glow haze, no bokeh, no painterly brush noise, no anti-aliased smoothing, no extra characters, no change of outfit or hair.

CHARACTER: <hier den Charakterblock einsetzen>
```

---

## CHARAKTERBLÖCKE

**Ellie** (Referenz: `ellie.png`; sie hat schon ein Porträt, nur für Varianten/neue Posen)
```
Ellie, young woman. Long silver-white hair with a heavy fringe, bright violet eyes. Fitted dark jacket, split plum-colored coat tails, dark violet-black clothing, small gold buckles/trim. Quiet, tired but determined face.
```

**Valdric, der Ritter** (`adventurer.png`; bereits Porträt v2, nur für Varianten, z. B. Helm ab ist NICHT festgelegt)
```
Valdric, tall adult knight of a wine-red order. Closed dark-steel helm with a narrow white-violet glowing visor slit and a short torn crest plume. Worn dark plate armor with lavender-grey light planes, gold trim, one huge spiked pauldron on the right shoulder, wine-red tabard and long cloak with hems darkened by void. Both gloved hands rest on a sword pommel at the hip, blade leaving the bottom edge. Calm, protective, mysterious.
```

**Gustav, der Zimmermann** (`gustav.png`; hat bereits ein Porträt, nur für Varianten)
```
Gustav, elderly carpenter. Cool grey tousled hair and a full grey moustache, weathered kind face, no stubble shadow, light blue eyes. Oat-colored shirt with rolled sleeves open at the collar, moss-green neckerchief, brown leather apron, a few sawdust specks in his hair. Warm, patient look.
```

**Torben, der Schmied** (`torben.png`; **noch kein Porträt**)
```
Torben, huge broad-shouldered blacksmith, much wider than the other characters. Dark brown short hair and a thick dark beard, strong brow, small dark eyes, soot smudges on the face. Bare muscular warm-brown arms, heavy brown leather apron over a dark undershirt with scorched patches, leather wrist guards, a glowing orange forge-heat tint only on his skin and on the iron he may hold at hip level. Gruff, stern, secretly gentle.
```

**Maren, die Stromhüterin** (`maren.png`; **noch kein Porträt**)
```
Maren, woman in her mid-30s, river keeper and fisher. Short practical light-brown hair (ear-length), weathered tanned face, sharp watchful eyes, faint smile lines. Grey-green waxed smock with a darker apron and rope belt, rolled sleeves, a fishing line coiled at the hip. Calm, patient, listening expression.
```

**Esma, die Nebelhexe** (`witch.png`; **noch kein Porträt**)
```
Esma, young witch of the mist. Very long straight dark-brown hair with a straight fringe, dark brown eyes, small silver hair clips, a round teal pendant at the throat. Striped wine-red and bone-white sleeves, dark plum-violet dress, tall pointed violet witch hat with a band and a small glinting buckle. Friendly, curious, slightly sly.
```

**Morwenna, die Spiegelhexe** (`morwenna.png`; Boss, **noch kein Porträt**)
```
Morwenna, the mirror witch. Pale grey-blue cold face, narrow eyes with faint green glints, long dark-violet layered cloak with tattered hems and glowing green points, tall crooked witch hat with bare twigs and antler-like branches, mirror shards sewn into the cloak. Cold, composed, dangerous.
```

---

## Hinweise zur Qualität

- Wenn Higgsfield den Ausschnitt nicht trifft: Zusatz `Crop exactly at the hip line, upper body only, tall 2:3 canvas` und Seitenverhältnis 2:3 einstellen.
- Wenn es zu weich/gemalt wird: Zusatz `flat vector-like color blocks, sharp stair-stepped edges, limited palette poster style`.
- Wenn das Gesicht zu realistisch wird: Zusatz `stylized game character, slightly larger head and eyes, simplified nose and mouth`.
- Nur **ein** Ausdruck pro Bild (neutral). Blinzel-/Mundformen backe ich selbst wie bei Gustav (`SpeechPortrait`).
- Sheets neu erzeugen: `py -3 tools/sheet_characters.py`.

---

## Ausdrucks-Reihe (Referenz = fertiges Porträt, 4 Gefühle nebeneinander)

Referenz hochladen: das Higgsfield-Porträt der Figur (z. B. `assets/ui/sources/higgsfield/ellie.png`), am besten auch den Master-Prompt-Charakterblock. Seitenverhältnis 8:3 (vier 2:3-Felder), sonst 21:9 und nachher zuschneiden. Pro Gefühl ein Feld.

```
Four character dialogue portraits of the SAME character side by side in one image, in a single horizontal row of four equal panels (each panel 2:3 portrait format), separated only by the flat magenta background. Use the attached portrait as the exact reference for identity, art style and framing: copy it 1:1 in all four panels: identical face shape, identical hair (length, parting, fringe, strand shapes, hair clip), identical eyes and eye colour, identical outfit, colours, outline, pixel-like chunky shapes, lighting and palette. Only the facial expression, eyebrows, mouth, eyelids and a very slight head tilt change.

CONSISTENCY (very important): same camera, same scale, same crop in every panel: head to hip, three-quarter view turned to the right, head top at about 4% from the top, eyes at about 24%, chin at about 36%, shoulders at 40-45%, cut off at the hips. Head size, eye height, shoulder line and body pose (arms, clothes) stay exactly the same in all four panels, nothing moves except the face. Light from the top left, same shading steps, same dark violet outline, same limited palette (about 30 colors), hard edges, no gradients, no blur.

PANELS, left to right:
1. LAUGHING: eyes happily narrowed into curved crescents, eyebrows raised and relaxed, wide open smiling mouth with teeth, cheeks lifted, a touch of rosy blush, head tipped slightly back.
2. SHOCKED: eyes wide open with small pupils, eyebrows high and arched, mouth open in a small round "o", a tiny sweat drop at the temple, head pulled slightly back.
3. TIRED: heavy half-closed eyelids, eyebrows low and slightly raised in the middle, faint dark circles under the eyes, mouth slightly open or flat, tired sigh, head tilted down a few degrees.
4. ANGRY: eyebrows pulled low and sharply inward, eyes narrowed and intense, glaring toward the right, teeth gritted or lips pressed into a hard line, nostrils tense, head slightly lowered.

BACKGROUND: perfectly flat solid pure magenta #FF00FF in all panels, no gradient, no shadow, no frame, no panel borders.

DO NOT: no text, no labels, no UI, no different outfit, no different hairstyle, no different eye colour, no change of art style between panels, no photo-realism, no 3D look, no extra characters, no full body.
```

Hinweise:
- Wenn die Gesichter zwischen den Feldern abweichen: Zusatz `Treat the panels like frames of one animation sheet: the face geometry is locked, only the expression changes`, oder jedes Gefühl einzeln mit derselben Referenz und demselben Seed generieren (nur die Zeile unter `PANELS` auf ein Gefühl kürzen und `single portrait` schreiben).
- Zu schwache Gefühle: `exaggerated anime-style expression, clearly readable at 103x153 pixels`.
- Danach schneide ich die Felder (je 1/4 der Breite) aus und rechne sie wie die anderen Porträts um.
