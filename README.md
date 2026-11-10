# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.6.1 Beta – „Hexenwald & Alchemie“

> Vollständige Versionshistorie, Studio-Log und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.6.1 Beta:
* **Neues Biom – Der Hexenwald (Region 31):** Über 38.000 neue Tiles nahtlos an der Südküste angeschlossen. Kühle Farbpalette, Schieferfelsen, Dauerdämmer und ein geschwungener Pfad zum Hexenturm.
* **Alchemie & Trankbrauen (Ablösung des Kochen-Systems):** Tränke in 5 Stufen (Wundtau für Sofortheilung, Glutatem für sekündliche Ausdauerschübe auch beim Sprinten). Eigene Trink-Animation im Lauf und Kampf.
* **Nebel des Wahns & Phantom-Kreaturen:** Giftgrüner Bodennebel mit Statuseffekt *Halluziniert*. Fortschreitender Trug (Flüstern, Schein-Items, zuckendes HUD und Phantom-Spinnen, die im Schlag zu Rauch verpuffen).
* **Esma die Nebelhexe & Der Hexenturm:** Vollständig ausgestattetes Turminneres mit Kessel, Kamin und Esmas animiertem Tagesablauf.
* **Kletterranken (Wall Climb):** Erklimmt steile Schieferwände direkt an bewachsenen Kletterranken mit flüssiger Kletter-Animation.
* **Der Krähenbaum & Klarglas-Ohrringe:** Monumentaler Rastbaum für gefiederte Begleiter und neuer Schutz-Talisman gegen den Nebelwahn.

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
