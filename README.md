# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.8.0 Beta – „Kristall, Seehexe & Federkiel“

> Vollständige Versionshistorie, Studio-Log und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.8.0 Beta:
* **Neues Magiesystem (5 Schulen · 50 Kristalle · 2 Stäbe):** Setzt geschliffene Verstärker und gewachsene Zauberkristalle (*Bannlicht, Wurzelgrund, Glutschwarm, Nebelschleier, Leerenschlund*) in den **Hexenulmenstab** oder den Doppelzinken-Stab **Bleichgabel** ein (*Gabelschlag, Gleichklang, Zwiespalt* – jeder Kristall trägt seine eigene Abklingzeit ohne Manaleiste!).
* **Die Seehexe Ilva & Ihr Pfahlhaus am Hexenwald-See:** Neuer Schauplatz am Westrand mit 9 Bannsteinen im `250 px` Schutzring (blockiert Halluzinationen), Einstiegsquest *„Der Ring am See“*, nächtlichem *Seeglimmer* und *Seemondstein*, kostenlosem *Läutern* und `3 → 1` *Schliff* bis Stufe V.
* **Das Neue Quest-Tagebuch (`J`) & Einzel-Fokus:** Illustriertes Buch mit *OFFEN*- und *ARCHIV*-Reitern, Ellies Erinnerungen & Tintenskizzen, Kartensprung, Abbrechen-Funktion und sauberem Einzel-Fokus für HUD-Zweig und Weltkarte.
* **Großes Charakter-Porträt-Overhaul:** Neue und überarbeitete `103 × 153` Pixel-Art-Porträts für **Torben, Esma, Morwenna, Maren, Valdric** und **Ellie**!
* **Einklappbare Hotbar (`6,5 s`) & Getrennte Koop-Spielstände:** Die Hotbar tuckt sich automatisch um `24 px` ein für mehr Spielfeldsicht; gehostete Koop-Welten nutzen einen eigenen Spielstand mit dauerhaften Gast-Identitäten für Inventare, Kristalle & Tagebuch.
* **Schwarzes Brett & Schwimm-Politur:** Bewohner hängen erst nach dem persönlichen Kennenlernen Aushänge aus; tiefes Wasser im Hexenwald-See aktiviert das Schwimmen wieder unmittelbar.

---

## 🗺️ Kern-Features
* **Host-Authoritatives Multiplayer-System:** Nahtloses Zusammenspiel von bis zu 4 Spielern (ENet / Godot Multiplayer) mit eigenem Koop-Spielstand und dauerhaften Gast-Identitäten.
* **Magie-System & Kristallhandwerk:** 5 Elementarschulen, `50` Sockel-Kristalle in 5 Seltenheiten, Einzel- und Doppelzinken-Stäbe bei Seehexe Ilva.
* **Dorfaufbau („Licht ist Land“):** Gebäude wachsen Pixel für Pixel (`build_pixels.gdshader`), getrampelte Pfade entstehen organisch zwischen Türen.
* **Lebendige Dorfbewohner, Tagebuch & Schwarzes Brett:** Echte Tagesabläufe für Valdric, Gustav, Torben, Esma und Ilva sowie Quest-Tagebuch (`J`), Kopfgelder und Ehrentafel.
* **Ackerbau & Selbstversorgung:** Felder bestellen, Saatgut züchten, Feuchtigkeitszyklen pflegen und Wundkräuter ernten.
* **Waffen-Veredelung (+1 bis +15):** Bei Torben dem Schmied mit Anschmieden, Härten und Leerenschmieden.
* **Dynamisches Beleuchtungs- und Wettersystem:** Globale Baumkronen-Deckungsmaske (`DaylightField`), Bannsteinring, 10 Wetterfronten, Wolken, Gewitterblitze und ständiges Wetter-HUD.
* **Mehrphasige Bosskämpfe:** Mornath (Sky Cleaver) und Morwenna (Spiegelhexe) mit herausfordernden Phasen, Nebeltarnungs-Reaktion, Glitch-Mechanik und dynamischen Arenen.

---

## 🛠️ Entwicklung & Tech-Stack
* **Engine:** Godot 4.7 (GDScript, strikte statische Typisierung)
* **Assets & Pipelines:** Deterministische Python-Art-Pipelines (`tools/`) für Pixel-Art, Shader und Normal-Maps
* **Datengetrieben:** Sämtliche Items, Gegner, Quests, Dialoge und Veredelungsregeln liegen in JSON (`data/`)

---

## 📦 Releases & Changelog
* Alle Releases und Patchnotes findest du unter **[GitHub Releases](https://github.com/acuteflower/shadowspore/releases)**.
* Der chronologische Update-Bericht liegt in **[`CHANGELOG.md`](CHANGELOG.md)**.
