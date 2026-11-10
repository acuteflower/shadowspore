# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.5.0 Beta – „Schwingen & Tiefen“

> Vollständige Versionshistorie, Studio-Log und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.5.0 Beta:
* **Oberflächenschwimmen & Gewässer:** Flüsse und Bergseen sind voll durchschwimmbar (Brustschwimmen, Kraulen mit Ausdauer, Wassertreten und Kopfsprung aus dem Sprint). Tiefes Wasser dient als sicherer Zufluchtsort vor Landmonstern.
* **Neues Wassermonster – Der Lichtfischer:** Schwimmt nachts in tiefen Gewässern und lockt Wanderer mit einer trügerischen Laterne an. Tödlicher Schnapp-Biss, Blendlicht und explosive Irrlichter.
* **Gefiederte Gefährten (Pet-System):** Zähmt wilde Krähen und Raben durch geduldiges Füttern! 6 Bindungsstufen, individuelle Charaktereigenschaften, Geschenke, Schultersitz und Warnrufe vor Nachtmonstern.
* **Legendäre Reliktwaffe – Himmelsriss:** Aus Mornaths Feder geschmiedete Klinge mit schnellem Doppelhieb (Rissschnitt & Himmelskreuz), fliegenden Projektilfedern und Leerenbahn-Spitzenriss.
* **Legendärer Talisman – Die Rissfeder:** Garantierter persönlicher Drop von Boss Mornath. Verhindert den Tod durch *Letzter Flügelschlag* (Überleben mit 30 % HP + Schockwelle) und verleiht *Sturzflug* (+40 % Schaden nach Schattensprüngen).

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
