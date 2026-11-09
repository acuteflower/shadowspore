# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.3.1 Beta

> Vollständige Versionshistorie und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.3.1 Beta:
* **Schwerer Angriff (Wuchtschlag - RMB / L2):** Zweistufig aufladbarer Rundumhieb (bis zu 3,4x Schaden und 3,0x Knockback) mit Schockwelle, Vorwärtsdrang und eigenen Charakter-Animationen (`player_heavy.png`).
* **Level-Fortschrittsfenster (Taste P):** Vollbild-Fortschrittsbaum über 4 Epochen mit entfaltenden Pixel-Blüten (`BloomOrb`), Meilenstein-Belohnungen, Rüstungswerten und Talisman-Slot-Freischaltungen.
* **Nacht-Director & Monster-Spawning Rework:** Taktische Monster-Wellen (Späher, Überfälle, Sammler, Letzter Ansturm), Mondphasen-Einfluss (Neumond +30 % Spawns) und akustische Spuren-Wahrnehmung.
* **Mornath-Arena Story & Hologramm:** Gefallener Arena-Ritter und holografische Projektion vor der Säulenebene zur narrativen Einstimmung.

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
