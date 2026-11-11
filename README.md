# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.8.1 Beta – „Schätze aus dem Licht“

> Vollständige Versionshistorie, Studio-Log und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.8.1 Beta:
* **Drei neue Beutetruhen-Klassen:** **Wurzelkiste** (Gewöhnlich, Schloss öffnen), **Mondsiegeltruhe** (Selten, `0,9 s` Siegel brechen) und **Glutreliquiar** (Legendär, `1,6 s` Leere-Ketten sprengen) – je mit eigenen Pixel-Art-Animationen, gestaffeltem Schatzregen (*das Beste zuletzt!*) und garantiertem Kristall-/Trank-Fund.
* **Spektakulärer Boss-Himmelssturz:** **Mornath** und **Morwenna** lassen `2,8 s` nach ihrem Tod ein legendäres **Glutreliquiar** in einer gigantischen Lichtsäule niederstürzen – inklusive ihrer kompletten Beute, Reliquien (*Rissfeder*, *Moras Spiegelscherbe*) und Bonus-Ziehungen (auch bei Rückkämpfen via Hologramm!).
* **Faire Koop-Beute & lange Liegezeit:** Truhen skalieren um **`+1` Extra-Ziehung** je nahem Mitspieler (`200 px` Radius), teilen Kupfer/XP gerecht unter allen Siegerinnen auf und lassen gedroppten Loot volle **`300 s` (5 Minuten)** liegen. Ungeöffnete Bosstruhen werden im Spielstand gesichert.
* **Vorbereiteter Ausblick:** Erste Art-Assets für kommende Welt-Rätsel (*Prüfungen der Wächterin*: Sonnenuhren, Runenstelen, Hortkrähen & Schreine) bereiten den Boden für künftige Erkundungs-Updates.

---

## 🗺️ Kern-Features
* **Host-Authoritatives Multiplayer-System:** Nahtloses Zusammenspiel von bis zu 4 Spielern (ENet / Godot Multiplayer) mit eigenem Koop-Spielstand und dauerhaften Gast-Identitäten.
* **Magie-System & Kristallhandwerk:** 5 Elementarschulen, `50` Sockel-Kristalle in 5 Seltenheiten, Einzel- und Doppelzinken-Stäbe bei Seehexe Ilva.
* **Dorfaufbau („Licht ist Land“):** Gebäude wachsen Pixel für Pixel (`build_pixels.gdshader`), getrampelte Pfade entstehen organisch zwischen Türen.
* **Lebendige Dorfbewohner, Tagebuch & Schwarzes Brett:** Echte Tagesabläufe für Valdric, Gustav, Torben, Esma und Ilva sowie Quest-Tagebuch (`J`), Kopfgelder und Ehrentafel.
* **Ackerbau & Selbstversorgung:** Felder bestellen, Saatgut züchten, Feuchtigkeitszyklen pflegen und Wundkräuter ernten.
* **Waffen-Veredelung (+1 bis +15):** Bei Torben dem Schmied mit Anschmieden, Härten und Leerenschmieden.
* **Dynamisches Beleuchtungs- und Wettersystem:** Globale Baumkronen-Deckungsmaske (`DaylightField`), Bannsteinring, 10 Wetterfronten, Wolken, Gewitterblitze und ständiges Wetter-HUD.
* **Mehrphasige Bosskämpfe & Beutetruhen:** Mornath (Sky Cleaver) und Morwenna (Spiegelhexe) mit herausfordernden Phasen, Nebeltarnungs-Reaktion, Glitch-Mechanik und legendären Boss-Reliquiaren aus dem Licht.

---

## 🛠️ Entwicklung & Tech-Stack
* **Engine:** Godot 4.7 (GDScript, strikte statische Typisierung)
* **Assets & Pipelines:** Deterministische Python-Art-Pipelines (`tools/`) für Pixel-Art, Shader und Normal-Maps
* **Datengetrieben:** Sämtliche Items, Gegner, Quests, Dialoge und Veredelungsregeln liegen in JSON (`data/`)

---

## 📦 Releases & Changelog
* Alle Releases und Patchnotes findest du unter **[GitHub Releases](https://github.com/acuteflower/shadowspore/releases)**.
* Der chronologische Update-Bericht liegt in **[`CHANGELOG.md`](CHANGELOG.md)**.
