# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.7.0 Beta – „Ernte, Sturm & Spiegelscherben“

> Vollständige Versionshistorie, Studio-Log und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.7.0 Beta:
* **Ackerbau & Farming-System (Kategorie ACKER):** Gustav schaltet die Scholle frei! Brecht den Boden mit der Hacke, pflanzt Knollenkeime, Glutmöhren, Nachtrüben und Wundblätter, gießt Beete mit der Gießkanne und sichert euch den Ernte-Pflegebonus.
* **Dynamisches Wettersystem & Himmelsfronten:** 10 dynamische Wetterlagen von strahlendem Sonnenschein bis zu tosenden Gewittern. Echte Wolkenschatten wandern über die Welt, Blitze erhellen die Nacht, und Regen gießt automatisch eure Felder.
* **Schwarzes Brett (Quest-Tafel im Dorf):** Der neue Mittelpunkt für Bürger-Aufträge, Kopfgelder und dörfliche Liefermissionen.
* **Voll spielbarer Bosskampf – Morwenna, die Spiegelhexe:** Besiegt die gefallene Großhexe am Großen Rabenbaum! Vollständiges 3-Phasen-Gefecht mit Glitch-Klonen, Klon-Tausch, Spiegelscherben-Käfig und Karussell-Angriffen.
* **Erweiterte Alchemie (Spezial- & Leere-Sude):** Braut Aschenhaut (Feuer-Immunität), Klarblick (Nebel- und Illusionsschutz), Irrlichtsud (Schattenbann) und Leere-Tränke mit bis zu 75 % Lebensraub.
* **Animations-Overhaul & Kampf-Polishing:** Komplett neu geglättete Animationszyklen für Laufen, Sprinten, Schleichen, Schwimmen und die 5-Stufen-Schwertkombo mit wuchtigem Hit-Feedback.

---

## 🗺️ Kern-Features
* **Host-Authoritatives Multiplayer-System:** Nahtloses Zusammenspiel von bis zu 4 Spielern (ENet / Godot Multiplayer).
* **Dorfaufbau („Licht ist Land“):** Gebäude wachsen Pixel für Pixel (`build_pixels.gdshader`), getrampelte Pfade entstehen organisch zwischen Türen.
* **Lebendige Dorfbewohner & Quests:** Echte Tagesabläufe für Valdric, Gustav und Torben sowie dynamische Anschläge am Schwarzen Brett.
* **Ackerbau & Selbstversorgung:** Felder bestellen, Saatgut züchten, Feuchtigkeitszyklen pflegen und Wundkräuter ernten.
* **Waffen-Veredelung (+1 bis +15):** Bei Torben dem Schmied mit Anschmieden, Härten und Leerenschmieden.
* **Dynamisches Beleuchtungs- und Wettersystem:** Globale Baumkronen-Deckungsmaske (`DaylightField`), 10 Wetterfronten, weltverankerte Wolken und Gewitterblitze.
* **Mehrphasige Bosskämpfe:** Mornath (Sky Cleaver) und Morwenna (Spiegelhexe) mit herausfordernden Phasen, Glitch-Mechanik und dynamischen Arenen.

---

## 🛠️ Entwicklung & Tech-Stack
* **Engine:** Godot 4.7 (GDScript, strikte statische Typisierung)
* **Assets & Pipelines:** Deterministische Python-Art-Pipelines (`tools/`) für Pixel-Art, Shader und Normal-Maps
* **Datengetrieben:** Sämtliche Items, Gegner, Quests, Dialoge und Veredelungsregeln liegen in JSON (`data/`)

---

## 📦 Releases & Changelog
* Alle Releases und Patchnotes findest du unter **[GitHub Releases](https://github.com/acuteflower/shadowspore/releases)**.
* Der chronologische Update-Bericht liegt in **[`CHANGELOG.md`](CHANGELOG.md)**.
