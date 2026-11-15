# Der Sternensaal & Die Göttin – Szenisches, Textur- & Animationskonzept

> **Status: Detailliertes Art-, Shader- & Szenenkonzept (Stand 2026-11-15).** Baut auf [goettin_konzept.md](goettin_konzept.md), [design_guide.md](design_guide.md), [dialogue_art.md](dialogue_art.md) und [waystones.md](waystones.md) auf.

---

## 1. Szenische Vision: „Mitten in der Leere der Sterne“

Der Sternensaal ist kein Zimmer mit Wänden, sondern eine **offene, schwebende Tempelinsel aus hellem Violett-Marmor und Gold**, die frei im tiefen Universum treibt.

* **Keine Wände, kein Dach:** Jenseits jeder Plattformkante fällt der Blick unmittelbar in den tiefen Kosmos – tausende gestochen scharfe Pixel-Sterne in mehreren Parallax-Ebenen, blasse türkis-goldene Sternennebel, langsam schwebende Marmor-Bruchstücke und ganz weit am Rand feine dunkle Risse der Leere.
* **Farbkontrast zur Leere:** Während die Leere tiefschwarz-violett mit Magenta-Gefahr wirkt, gehört der Saal der **Kombination aus hellem Mond-Violettmarmor, antikem Gold (`#e6c468` / `#fff0b0`), ruhigem Türkis-Leuchten (`#3cc0c6` / `#d0fff8`) und sternenhellem Elfenbein (`#e9e3f7` / `#fffaf0`)**.
* **Keine Tag-Nacht-Verdunklung:** Der Saal nutzt konstantes, klares Sternenlicht (`ambient` kühl-silberblau) plus kräftige `Unlit`-/`emissive`-Schichten (`*_glow.png`), damit Leylines, Spiegelbecken, Kristallkandelaber und der Heiligenschein der Göttin traumhaft strahlen.

---

## 2. Raum-Aufbau & Exakte Maße (`560 × 820` px)

Ursprung `(0, 0)` oben links, Mittelachse `X = 280`. Begehbarer Bereich ist rein aus der Plattformgeometrie geformt; jenseits der Kanten liegt der offene Abgrund ins All.

| Zone | Y-Bereich | Breite / Form | Inhalt & Atmosphäre |
|---|---|---|---|
| **1. Ankunftskreis (Süden)** | `640 .. 770` | Runde/elliptische Plattform (`rx ≈ 96`, `ry ≈ 58`) | Eingelassener Runenring aus 16 Steinkacheln, zwei niedrige Eck-Pylone mit türkis-weißem Sternenfeuer, zarte Marmor-Stufen zur Brücke. Mittig bei `(280, 715)` schwebt der **Rückkehr-Anker** (`return_seal`: rotierender Runenring + `E ZURÜCKKEHREN`). |
| **2. Offene Sternenbrücke (Mitte)** | `270 .. 640` | Hauptgang (`X = 202 .. 358`, `156 px` breit) + zwei ausladende Seiten-Balkone | Handgelegter heller Violett-Marmor mit goldenen Sternenlinien, türkis glühenden Leylines und **zwei eingelassenen Spiegelbecken** links/rechts (`X = 166..218` und `342..394`, `Y = 395..565`). Flankiert von **6 Kristall-Kandelabern (3 Paare)** und niedrigen, offenen Balustraden mit Durchblick ins All. |
| **3. Thron-Podest (Norden)** | `70 .. 270` | Halbkreisförmiges Podest (`rx ≈ 140`, `ry ≈ 88`) über 3 breite Stufen (`Y = 248..272`) | Drei leuchtende Marmorstufen führen auf das Podest. Im Zentrum `(280, 178)` eine große eingelassene **Astrolab-Sternenrosette**. Bei `(280, 162)` steht der monumentale **Göttliche Thron**, darauf die sitzende Göttin. Links, rechts und vorne-seitlich drei vorbereitete **Reliquien-Sockel** für künftige Gaben. |
| **Außen-Kosmos** | außerhalb der Insel | Freier Raum rundum | 4–6 **schwebende Marmor- & Kristall-Inselfragmente** in verschiedenen Größen treiben langsam vertikal (`sin(time)` in ganzen Pixeln) neben der Brücke und hinter dem Thron. Unter den Plattformkanten hängen gebrochene, schwebende Stein-Zacken, damit die Platte erkennbar *im Raum schwebt*. |

### Welt-gekoppelte Licht-Progression
* Die drei Paare Kristall-Kandelaber (Süd, Mitte, Nord) sowie die verbindenden Boden-Leylines schalten sich entlang von `Waystones.awake_count()` von Süd nach Nord hinzu (beim ersten Rettungsbesuch leuchten bereits das Süd-Paar, das Ankunftssiegel und der Thron-Kranz).

---

## 3. Texturen, Shader & Umgebungs-Animationen (`starhall-art`)

### 3.1 Farbpaletten (abgeleitet aus [design_guide.md](design_guide.md) & [art_waystone.py](tools/art_waystone.py))
* **Heller Sternen-Marmor:** `#2f2d4b` → `#504e7c` → `#8583ae` → `#d4d2ea` (Schatten immer kühl-violett, nie neutralgrau; Rand `#17142a`).
* **Unterseite / Schwebekante:** `#141024` → `#221d3a` → `#3a365c` (Felszacken unter dem Boden).
* **Gold-Intarsien & Thronfiligran:** `#6f5020` → `#b48a38` → `#e6c468` → `#fff0b0`.
* **Türkis-Leylines & Sternenlicht (`Unlit`):** `#2a8c94` → `#3cc0c6` → `#78f4e6` → `#d0fff8`.
* **Kosmos-Tiefe:** `#040208` → `#09060f` → `#120b24` → `#1e1438` + blasse Nebel in `#173440` / `#2a8c94`.

### 3.2 Benötigte Shader
1. **`assets/shaders/starhall_cosmos.gdshader`** (`render_mode unshaded`, weltverankert per `floor(UV * rect_size)`):
   * Tiefschwarz-violetter Raum mit langsam ziehenden, **Bayer-geditherten Nebelbändern** (kühles Türkis-Blau und zartes Sternen-Violett).
   * **4 Parallax-Schichten von Pixel-Sternen:** feine `1×1`-Sterne, helle blassblaue Sterne, und größere `3×3`-Kreuzsterne in Gold (`#fff0b0`) & Türkis (`#d0fff8`), die sanft und phasenversetzt funkeln.
   * Am äußersten Rand weitab der Plattform subtile dunkle, violett glimmende **Leeren-Risse** (Kontrast-Erzählung).
   * Weicher, geditherter **Sternenstaub-Schimmer** um die Plattform-Kontur, sodass das schwebende Steinwerk nahtlos im Licht ruht.
2. **`assets/shaders/starhall_mirror.gdshader`** (`render_mode unshaded`):
   * Für die zwei flachen Spiegelbecken auf der Sternenbrücke: tiefes Nacht-Saphir/Violett mit reflektierten, langsam ziehenden Pixel-Sternen, horizontalen Pixel-Wasserwellen und zarten türkisen Lichtreflexen entlang der Beckenränder.

### 3.3 Generierte Texturen & Animationen (`tools/art_starhall.py` → `assets/interior/starhall/`)
Alle PNGs scharf gepixelt, ohne Weichzeichnung, mit separater `*_glow.png` für alle selbstleuchtenden Pixel:

1. **`floor_base.png` & `floor_glow.png` (`560 × 820`):**
   * Ankunftskreis, Sternenbrücke mit Plattenfugen, Seiten-Balkone, Stufen zum Podest, Thron-Podest mit großer gold-türkiser Astrolab-Rosette, sowie die plastischen schwebenden Fels-/Marmor-Zacken unter den Südrändern.
2. **`throne.png` & `throne_glow.png` (animiert: `8 Frames`, z. B. `160 × 176` pro Frame, Fußpunkt `(80, 148)`):**
   * Monumentaler Thron aus Mond-Marmor mit geschwungener hoher Lehne, goldenen Flügel-Ornamenten, tiefblau-pflaumenem Polster (`#1e1a36` / `#34284e` mit Goldborte) und hinter der Lehne einem großen **rotierend/pulsierend animierten Sonnen- & Kristallkranz** (8 Kristallstrahlen + drehender goldener Astrolab-Ring).
3. **`pylon.png` & `pylon_glow.png` (`8 Frames`, z. B. `48 × 96` pro Frame, Fußpunkt `(24, 84)`):**
   * Schlanke, teils schwebende Marmorsäule mit goldener Fassung oben; zwischen ihren Spitzen schwebt und atmet ein leuchtender türkis-goldener Sternkristall (auf/ab + Kristallglanz-Schimmer über 8 Frames).
4. **`balustrade.png` & `balustrade_glow.png` (`48 × 36` bzw. Segmente):**
   * Niedrige durchbrochene Marmor-Geländer mit feinen Goldkappen und kleinen Runenpunkten.
5. **`return_seal.png` & `return_seal_glow.png` (`8 Frames`, `64 × 44` pro Frame):**
   * Schwebender türkis-goldener Siegelring knapp über dem Ankunftskreis (langsame Rotation + aufsteigende Runenfunken).
6. **`relic_plinth.png` & `relic_plinth_glow.png` (`8 Frames`, `36 × 52` pro Frame):**
   * Schwebender Kristall-Sockel am Rand des Thron-Podests für künftige Gaben.
7. **`cosmos_island_0..2.png` & `*_glow.png` (3 Varianten schwebender Außen-Fragmente):**
   * Treibende Stein-/Marmorbrocken mit kleinen Kristall-Adern für den äußeren Parallax-Raum.
8. **`star_mote.png` (`4 Frames`, `8 × 8`):**
   * Zarte funkelnde Sternen-Lichtmotten für Partikelsysteme im Saal.

### 3.4 Vorschau-Szene (`tools/preview_starhall.tscn` + `.gd`)
* Baut den kompletten Saal mit `starhall_cosmos.gdshader`, `floor_base/glow`, zwei `starhall_mirror`-Becken, 6 animierten Pylonen, Thron, schwebenden Außen-Fragmenten, Partikeln (`star_mote`) und (falls vorhanden) der Göttin auf.
* Unterstützt `-- --dir=<abs_dir>` und rendert Gesamtansicht + Nahaufnahme Thron + Nahaufnahme Brücke als PNGs zur direkten visuellen Prüfung.

---

## 4. Charakter-Art & Animationen: Die Göttin (`goddess-art`)

Eine **wunderschöne göttliche Jungfrau** – anmutig, ruhig, lebendig und sofort erkennbar als Urbild der Wegstein-Statuen.

### 4.1 Pipeline & Maßstab
* **Pipeline:** Erstellt per prozeduralem 3D-Ellipsoid-Renderer auf Basis von `tools/art_hero3d.py` / `tools/art_waystone.py` (`tools/art_goddess.py`) mit der projekteinheitlichen Körnung, 4-stufigen Tonbändern und dunkel getönter `1 px`-Outline.
* **Framegröße & Größe im Spiel:** `FW = 96, FH = 112`, `GROUND_ROW = 94` (Fuß-/Sitzanker `(48, 94)`). Die Figur misst ca. **1,6× Ellie** (~`66 px` stehend gedacht; auf dem Thron sitzend genau auf die Thronhöhe von `throne.png` abgestimmt!).
* **Zwei Sheets:** `assets/characters/goddess.png` + `assets/characters/goddess_glow.png` (nur `Unlit`-Pixel: Augen, Heiligenschein, schwebende Kristallspitzen, türkise Gewandadern, Handfunke) + `data/goddess_rig.json`.

### 4.2 Wunderschöne Gestaltung im Detail
* **Gesicht & Ausdruck:** Zarte Porzellan-Haut (`#dc9496`, `#f2b8b2`, `#fde0d2`, `#fff3e8`), fein geformte Nase, sanfte Rosenlippen (`#84405a`..`#f0b2c2`), **ausdrucksstarke leuchtende türkis-weiße Augen (`#2a8c94` / `#3cc0c6` / `#78f4e6` / `#d0fff8`)** unter fein geschwungenen Brauen.
* **Haar & Diadem:** Langes, voluminöses, weich fließendes **Silber-Lichtgold-Haar** (`#8f84c2` / `#bdb3e4` / `#e9e3f7` / `#fffaf0` + warme Goldlicht-Strähnen), Mittelscheitel, zwei schmale Schläfenzöpfe und ein filigranes **goldenes Sternen-Diadem** mit winzigem Türkisstein auf der Stirn. Langes Haar fällt über Schultern und Arme herab und wiegt sanft.
* **Gewand & Schleier:** Fließendes, göttliches Kleid in Mond-Elfenbein und Nachtblau-Violett (`#1e1a36`, `#2a2548`, `#4a4180`, `#d4d2ea`) mit eleganter hoher Taille, **goldenen Schulterspangen & Gürtelborte** (`#6f5020`..`#fff0b0`), langem geteiltem Rockfall über die Thronstufen und einem zarten, leicht schwebenden **Schulter-Schleier** mit türkisen Lichtadern am Saum.
* **Heiligenschein:** Schwebender goldener Bogen + feine facettierte Kristall-Zacken hinter dem Kopf (in `goddess_glow.png` strahlend).

### 4.3 Animations-Clips (`assets/characters/goddess.png`, Süd-/Frontsicht + sanfte Blickwinkel)
1. **`sit_idle` (6 Frames, Loop, 6 fps):** Ruhige thronende Haltung (ein Bein leicht vorgesetzt, linke Hand ruht elegant auf der Lehne, rechte hält einen kleinen schwebenden Sternenfunken); ruhiges Atmen, weich wehendes Haar und Schleier.
2. **`sit_talk` (6 Frames, Loop, 7 fps):** Freundliches leichtes Vorbeugen/Zuwenden, elegante einladende Handbewegung, leichtes Pulsieren der Augen/Kristalle.
3. **`sit_bless` (8 Frames, 8 fps):** Feierliche Segnungs-Pose – beide Hände heben sich anmutig nach vorn/oben, Haar und Schleier schweben leicht aufwärts, zwischen den Händen wächst ein gold-türkiser Lichtstern, Heiligenschein und Gewandadern blühen hell auf.
4. **`stand_idle` (6 Frames, Loop, 6 fps):** Stehende majestätische Pose (für besondere Szenen oder Vorschau/Referenz).

### 4.4 Dialog-Portrait (`assets/ui/portrait_goddess.png`)
* Nach den Regeln von [dialogue_art.md](dialogue_art.md): `103 × 153` logische Pixel pro Zelle als **`2 × 1`-Sheet (`206 × 153`)** – links **Augen offen**, rechts **Zwinkern (`blink`)** (identische Kopf-/Schulteranker für `dialogue_portrait.gdshader`, Kopf-bis-Hüfte-Ausschnitt, sanfter 3/4-Blick zur Textbox).
* **Eigener Python-Generator (`tools/art_goddess_portrait.py` oder direkt in `tools/art_goddess.py`)** + **Vorschau-Szene (`tools/preview_goddess.tscn` + `.gd`)**, die alle Clips auf einem dunklen Sternenhintergrund + das Dialogportrait nebeneinander als PNGs unter `-- --dir=<abs_dir>` exportiert.
