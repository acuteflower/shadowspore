# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.4.0 Beta

> Vollständige Versionshistorie und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.4.0 Beta:
* **Atmosphärisches Hauptmenü & Launcher:** Komplettes Hauptmenü mit lebendiger Live-Kulisse (`menu_world.gd`), Tag-Nacht-Licht, Einzelspieler, Host/Join-Koop mit direkter IP-Eingabe, Optionen und Speicherstand-Verwaltung.
* **5-Stufen-Schwertkombo & Finisher:** Erweiterung der Grundkombo um freischaltbaren *Aufwärtshieb* (Schlag 4, 1,25x Schaden) und verheerende *Wirbelklinge* (Schlag 5, 1,8x Schaden, 330°-Rundumschlag) mit eigenem Animationssheet (`player_combo.png`).
* **Schleiergeflecht & Fähigkeitenbaum-Rework:** Rankendes Fertigkeitennetzwerk für Kampf, Bewegung und Schatten mit handgepixelten Icons, Leuchteffekten und neuem *Schleichen*-Skill.
* **Talisman-System & Tragbarer Schmuck:** Halsketten, Armbänder und Ohrringe mit spürbaren Boni (z. B. Silberkette, Wuchtreif, Schweigtropfen). Angelegter Schmuck wird sichtbar auf der Spielfigur gerendert.
* **Modulare Kisten & Truhen:** Neues Kisten-System (`ItemBox` & `BoxWindow`) für komfortables Verstauen mit Shift-Klick, Schnell-Stapeln (`Quick Stack`) und Sortierung.

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
