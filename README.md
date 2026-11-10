# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.6.2 Beta – „Echo der Zerrissenen“

> Vollständige Versionshistorie, Studio-Log und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.6.2 Beta:
* **Boss 2 – Morwenna, die Spiegelhexe:** Die gefallene Großhexe am monumentalen Rabenbaum im Schieferkessel! Unberechenbare Glitch-Mechanik mit Micro-Stutter, zweistimmiger Sprachüberlagerung und permanenten Glitch-Klonen (überwacht von kreisenden Raben).
* **Höhenstufen-Verdeckung & Relief-Schatten:** Echtes `ReliefOverhang`-System – Klippen und Felsplateaus verdecken darunterstehende Figuren perspektivisch korrekt und werfen saubere Schattensäume.
* **Mornath-Arena & Schockwellen-Rework:** Vollständig überarbeitete Schockwellen-Geometrie (`ShockRing`) mit radialer Segmentierung, geglättete Brandflächen (`PixelFlames`) und geschärfte Risswände.
* **Kontextsensitiver Cursor & Schadenszahlen-Overhaul:** 5 dynamische Cursor-Glyphen (Fernkampf, Ernte, Klettern, Vogel-Interaktion, Nahkampf) und bogenförmig federnde Schadenszahlen mit Crit-Hervorhebung.
* **Lebendige Wildnis & Schritt-Partikel:** Bären, Kaninchen und Krähen reagieren auf Nachtphasen und Fackellicht; Stiefelschritte erzeugen materialspezifische Staub-, Wasser- und Schlammeffekte.
* **Atmosphärische Abgründe (Void Edge):** Brodelnde Leere-Zungen und schwebende Partikel säumen die Kanten der schwebenden Inselwelt.

---

## 🗺️ Kern-Features
* **Host-Authoritatives Multiplayer-System:** Nahtloses Zusammenspiel von bis zu 4 Spielern (ENet / Godot Multiplayer).
* **Dorfaufbau („Licht ist Land“):** Gebäude wachsen Pixel für Pixel (`build_pixels.gdshader`), getrampelte Pfade entstehen organisch zwischen Türen.
* **Lebendige Dorfbewohner:** Echte Tagesabläufe für Valdric, Gustav und Torben.
* **Waffen-Veredelung (+1 bis +15):** Bei Torben dem Schmied mit Anschmieden, Härten und Leerenschmieden.
* **Dynamisches Beleuchtungs- und Wettersystem:** Globale Baumkronen-Deckungsmaske (`DaylightField`), weltverankerte Wolken und stimmungsvolle Lichtschäfte.
* **Mehrphasige Bosskämpfe:** Mornath (Sky Cleaver) mit 3 herausfordernden Phasen, Zorn-Mechanik und Feuer-Arena.

---

## 🛠️ Entwicklung & Tech-Stack
* **Engine:** Godot 4.7 (GDScript, strikte statische Typisierung)
* **Assets & Pipelines:** Deterministische Python-Art-Pipelines (`tools/`) für Pixel-Art, Shader und Normal-Maps
* **Datengetrieben:** Sämtliche Items, Gegner, Quests, Dialoge und Veredelungsregeln liegen in JSON (`data/`)

---

## 📦 Releases & Changelog
* Alle Releases und Patchnotes findest du unter **[GitHub Releases](https://github.com/acuteflower/shadowspore/releases)**.
* Der chronologische Update-Bericht liegt in **[`CHANGELOG.md`](CHANGELOG.md)**.
