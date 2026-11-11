# Shadowspore

**Shadowspore** ist ein atmosphärisches 2D-Pixel-Art Top-Down (3/4) Action-RPG, entwickelt in Godot 4.7 (GDScript).
Es kombiniert Base-Building, Dorfaufbau, Landwirtschaft, Survival bei Nacht und dynamische Bosskämpfe mit anspruchsvollem Kampf- und Veredelungssystem (1–4 Spieler, host-authoritativ).

---

## 🚀 Aktuelle Version: V0.7.1 Beta – „Risse in der Leere & Gedächtnis der Stadt“

> Vollständige Versionshistorie, Studio-Log und alle Detailwerte: siehe **[`CHANGELOG.md`](CHANGELOG.md)**.

### Highlights von V0.7.1 Beta:
* **Neue Leere-Fähigkeit – Schattenschritt (`Alt` / Gamepad `B`):** Ersetzt den alten Schattenblink im umbenannten Zweig **LEERE**! Ein reaktionsschneller Ausweichschritt (`54 px`, `0,8 s` CD, `0,26 s` Schutzfenster), der laufende Kombos, Heavy-Charges und Aktionen sofort abbricht und durch spektakuläre Leere-Risse führt.
* **Großer Ausbau des Schwarzen Bretts („Das Gedächtnis der Stadt“):** Die lebende Tafel zeigt jetzt alternde Zettel, aufsteigende Knospenlichter, Wind- & Nässe-Effekte sowie abziehende Dorfkrähen! Hinzu kommen **6 reaktive Stadt-Anlässe**, **Eilzettel mit rotem Wachssiegel** (doppelter Lohn), direktes Melden beim Auftraggeber (inkl. Esma), eine **Ehrentafel mit 7 tragbaren Titeln** und ein wachsendes Brett (bis `6` Plätze).
* **Steckbriefe & Gezeichnete Elites:** Entkommt ein Elite nachts dem Morgengrauen, flieht er mit eigenem Namen und kehrt zäher (`+10 %` HP je Nacht) zurück. Am Brett hängt sein Steckbrief mit Tintenskizze – jeder Koop-Spieler, der ihn trifft, erhält das volle Kopfgeld!
* **Quest-Ast & Karten-Integration:** Bis zu `3` angenommene Zettel hängen als Nebenzweige im HUD (mit Eil-Fristring); auf der Karte erscheinen Fundbereiche, Einsatzkreise, Auftraggeber-Pins und magenta Steckbrief-Fadenkreuze.
* **Hexenwald-See & Flussverbindungen:** Ein neuer `28 × 24` Kacheln großer Binnensee im tiefen Hexenwald samt zwei neuen Flussverbindungen; schmale Bäche durchwatet Ellie jetzt bequem vor dem Schwimmen.
* **Dreistufiges Gangarten-System (`Sprint 124 px/s`) & Wetter-HUD:** Neues aufrechtes Joggen passend zur echten Geschwindigkeit, ruhigeres Gehen, aufrechteres Schleichen, weichere Wolkenränder, lebendigere Regentropfen und ein immer sichtbares animiertes Wettericon direkt an der Uhr.

---

## 🗺️ Kern-Features
* **Host-Authoritatives Multiplayer-System:** Nahtloses Zusammenspiel von bis zu 4 Spielern (ENet / Godot Multiplayer).
* **Dorfaufbau („Licht ist Land“):** Gebäude wachsen Pixel für Pixel (`build_pixels.gdshader`), getrampelte Pfade entstehen organisch zwischen Türen.
* **Lebendige Dorfbewohner & Schwarzes Brett:** Echte Tagesabläufe für Valdric, Gustav, Torben und Esma sowie ein reaktives Auftrags-, Steckbrief- und Ehrensystem.
* **Ackerbau & Selbstversorgung:** Felder bestellen, Saatgut züchten, Feuchtigkeitszyklen pflegen und Wundkräuter ernten.
* **Waffen-Veredelung (+1 bis +15):** Bei Torben dem Schmied mit Anschmieden, Härten und Leerenschmieden.
* **Dynamisches Beleuchtungs- und Wettersystem:** Globale Baumkronen-Deckungsmaske (`DaylightField`), 10 Wetterfronten, weltverankerte Wolken, Gewitterblitze und ständiges Wetter-HUD.
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
