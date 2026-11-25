# Caelia & Der Interstellare Raum – Gesamtkonzept

> **Status: Abgestimmtes Konzept (2026-11-23).**
> Dieses Konzept entwirft Caelias Bereich, die schwerelose Bewegung, Ellies Zero-G-Animationen, das ultrarealistische Weltraum-Parallax und Caelias komplettes Redesign von Grund auf neu – eingebettet in Shadowspores Architektur, Pixel-Art-Regeln ([design_guide.md](design_guide.md)) und Lore ([storyboard.md](storyboard.md)). Schwebende Props und Detail-Objekte folgen in einer späteren Phase auf dem hier gelegten Zero-G-Fundament.

---

## 1. Leitvision: Vom Marmor-Saal ins freie All

* **Kein Boden, keine Wände, keine Brücken, kein Thron.** Caelias Bereich ist eine ruhige, offene Lichtung **mitten im freien interstellaren Raum** – schwerelos, still, weit und tief.
* **Lore-Verankerung ([storyboard.md](storyboard.md)):** Die Leere ist das hungrige Nichts *zwischen* den Sternen; der Schleier ist das Gewebe aus Sternenlicht und Erinnerung. Caelias alte Tempel aus Stein zerbrachen im Großen Riss. Ihr eigentlicher Ort liegt unmittelbar im freien Kosmos.
* **Zukunftssicheres Fundament („Alles schwebt später“):** Der Raum startet puristisch (freies All, Caelia und der schwebende Rückkehr-Anker), trägt aber bereits das Zero-G-Drift-Fundament für künftige schwebende Props, die fünf Siegel des Schleiers im Orbit und künftige Gaben-Konstellationen.

---

## 2. Raumaufbau & Sanfter Schleier-Horizont

* **Größe & eigenes Pocket-Band:** Offener kreisförmiger Flugraum (`2200 × 2200 px`, Nutzradius `R_max = 1050 px`, Zentrum `(1100, 1100)`), in einem eigenen Pocket-Koordinatenbereich getrennt vom regulären `Interiors.SLOT = 1600`-Streifen und der Mine.
* **Zentrum `(1100, 1100)`:** Frei schwebende Caelia in einer ruhigen Sternenlicht-Lichtung.
* **Ankunfts- & Rückkehr-Anker `(1100, 1390)`:** Frei schwebender Astrolab-Lichtriss (`290 px` südlich von Caelia, damit Ellie nach der Ankunft ein spürbares Stück durchs Parallax auf Caelia zuschwebt).
* **Sanfter Schleier-Horizont (`R_soft = 760 px .. R_max = 1050 px`):** Keine harten unsichtbaren Wände! Jenseits von `760 px` intensivieren sich ferne Leeren-Risse am Rand, Lichtfäden ziehen sanft nach innen, und eine glatt ansteigende quadratische Rückholkraft biegt Ellies Flugbahn elastisch in einem weichen Bogen zurück Richtung Zentrum.

---

## 3. Ultrarealistisches 8-Ebenen-Interstellar-Parallax

Scharfes `640 × 360`-Pixel-Art ohne Weichzeichnen, kamera-verankert, mit ganzzahligem Pixel-Snapping (`floor(cam_pos * factor)`) pro Ebene:

| Ebene | Faktor | Inhalt |
|---|---:|---|
| 0 | `0.008` | Diagonale Milchstraße mit dunklen Staub-Absorptionskanälen (*Dark Dust Lanes*) & winzigen fernen Galaxien |
| 1 | `0.022` | Dichtes `1×1`-Spektral-Sternenfeld (O/B/A/F/G/K/M, Potenzgesetz-Helligkeit, ruhiges Vakuum ohne Luftflackern, verdeckt von Staubkanälen) |
| 2 | `0.045` | Ferne astronomische Landmarken (dunkler, halb im Schatten liegender Ringkörper am fernen Horizont + ferne Leeren-Narben am Rand) |
| 3 | `0.080` | Tiefer Bayer-4×4-geditherter Kosmos-Nebel (Tiefsaphir, Indigo, hauchfeine Goldstaub-Kanten) |
| 4 | `0.155` | Zweite, unabhängig gleitende transparente Türkis-Ionisations- & Rauch-Schleierschicht über Ebene 3 (echtes 3D-Volumen!) |
| 5 | `0.26` / `0.40` | Nahe Leit- & Doppelsterne mit scharfen `3×3`-/`5×5`-Beugungskreuzen |
| 6 | `0.58` / `0.78` | Nahe glitzernde Eiskristall- & Staubpartikel hinter Ellie (Speed-Cues) |
| 7 | `1.00` | Spiel-Ebene (Ellie, Caelia, Mitspieler, Rückkehr-Riss) + lokaler reaktiver Sternenstaub (Kielwasser) |
| 8 | `1.22` / `1.38` | Sparsamer Vordergrund-Tiefenstaub *vor* Ellie & Caelia (`Unlit`, räumliche Immersion) |

---

## 4. Ellies Schwerelos-Bewegung (`ZeroGRules` + `ZeroGComponent`, `data/zero_g.json`)

* **Fluid Zero-G:** Sanftes Beschleunigen (`WASD`/Stick), seidiges Ausgleiten (`drag ≈ 1.15/s`), weiches 360°-Kurven-Carving mit `2,1×` Gegenimpuls beim Umkehren, sanfte Stabilisierung unter `10 px/s`.
* **`Shift` → Boost-Glide:** Schnelles, langgestrecktes Sternengleiten (`~155 px/s`) mit kleinem Abstoß-Impuls & Sternenstaub-Schweif, **ohne Ausdauerverbrauch**.
* **`Strg` / `C` → Hover-Brake:** Sanftes Abbremsen (`brake_drag ≈ 4.8/s`) und ruhiges Feinschweben (`~34 px/s`).
* **`Alt` → Astral-Schwung:** Elegantes Gleiten über den Schritt hinaus mit teilweiser Momentum-Übernahme (gold-türkis nach `LICHTSCHRITT`).
* **Atmosphäre:** Kein Bodenschatten, keine Schrittgeräusche, kein Staub, ruhiger Lissajous-Idle-Drift, elastischer Zero-G-Kamera-Lead & sanfte Caelia-Rahmung.

---

## 5. Ellies Zero-G-Texturen & -Animationen (`tools/art_hero_float.py`)

* `assets/characters/player_float.png` + `player_float_blood.png` + `data/hero_rig.json` `"float"`.
* `64 × 64 px`, Schwerpunkt-Anker `(32, 34)`, **8 echte Blickrichtungen** (`E..NE`), kein Bodenschatten, schwerelos auffächerndes silberweißes Haar & wogende Mantelschöße.
* **Clips:** `float_idle` (8f), `drift` (8f), `glide` (8f), `brake` (6f), `arrive` (10f), `float_standby` (16f).

---

## 6. Caelias Komplett-Redesign (`tools/art_goddess.py` & `portrait_goddess.png`)

* **Frei schwebende Göttin im All** (`128 × 144 px`, Anker `(64, 76)`, **8 echte Richtungen `E..NE`**, 1,7× Ellie):
  * Barfuß mit feinen schwebenden goldenen Knöchelreifen, asymmetrisch schwerelos hängende Beine.
  * Fließendes, asymmetrisch drapiertes **Mond-Elfenbein-Gewand**, das sich nach unten in wogende Licht- & Stoffbahnen auflöst (kein Korsett!).
  * Freischwebende **nachtblaue Himmels-Stola** (*Astral Ribbon*) mit glühenden türkis-goldenen Sternbild-Linien.
  * **Sternenfluss-Haar (*Living Nebula Hair*):** Mond-Silber am Kopf, das zu den Spitzen ins tiefe Kosmos-Indigo mit einzelnen `1×1`-Sternenpunkten übergeht.
  * **Schwebendes Astrolab:** 2–3 schräg geneigte, gegenläufig kreisende goldene Lichtringe in echter 3D-Tiefe mit dynamischen Lichtknoten (wachsen mit erwachten Wegsteinen).
  * Subtile goldene Kintsugi-Lichtnarbe an einer Schulter; ruhige leuchtende Mond-Türkis-Augen.
* **Clips:** `float_idle` (8f), `float_talk` (8f), `float_bless` (12f) + `goddess_glow.png`, plus sanfte 360°-Nachführung und Raum-Atmung in `StarHallGoddess`.
* **Neues Dialog-Portrait:** `assets/ui/portrait_goddess.png` (`206 × 153`: offen + Zwinkern in `103 × 153` nach [dialogue_art.md](dialogue_art.md)).
