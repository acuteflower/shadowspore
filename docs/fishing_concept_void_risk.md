# Game Design & Architektur-Konzept: Schatten- & Schleier-Angeln in Shadowspore

**Autor:** Konzepter 2 – Fokus: *Schatten- & Schleier-Angeln (Risk & Reward, Nacht-Spannung & Leeren-Ökologie)*  
**Projekt:** Shadowspore (Godot 4.7 / GDScript, 2D Top-Down Action-RPG, 640×360 Pixel, 1–4 Spieler Co-op)  
**Status:** Vollständiger Konzeptentwurf  

---

## 1. Kernvision & Philosophie

### 1.1 Name des Systems & Leitgedanke
* **Systemname:** **Schleier-Angeln** *(Veil Angling)* – in der Spielwelt oft ehrfürchtig als *„Der Blick in den Schlund“* bezeichnet.
* **Leitmotiv:**  
  > *„Wer am Tage die Schnur auswirft, nährt den Leib. Wer bei Nacht in den Fluss lauscht, dem blickt die Tiefe entgegen.“*

### 1.2 Warum Schleier-Angeln Shadowspore transformiert
In vielen klassischen RPGs ist das Angeln eine isolierte, meditative Nebenbeschäftigung – ein rein mechanischer Zeitvertreib zum Sammeln von Kochzutaten oder Trophäen. In Shadowspore darf Angeln kein generisches Minispiel sein.

Das Schleier-Angeln verbindet die ruhige Schönheit der Fluss- und Seenlandschaften (`docs/water_design.md`, `docs/water_life.md`) mit der existentiellen Kernspannung des Spiels: **Tag vs. Nacht**, **„Licht ist Land“ vs. die lauernde Dunkelheit** (`docs/nacht_monster_konzept.md`) und dem mystischen **Schleiergeflecht** (`docs/skill_tree.md`).

Während der 8-minütige Tag friedliche Ufer, fließende Reflexe und nahrhafte Speisefische bietet, verwandelt die 4-minütige Nacht die Gewässer in dunkle, pulsierende Adern der Leere. Die wertvollsten Schätze, alchemistischen Essenzen und Schleier-Knoten-Relikte existieren tief unter der Wasseroberfläche in den versunkenen Schluchten. Doch wer diese Schätze bergen will, muss die Sicherheit der befestigten Stadt (`TownManager`) und ihrer Lichtkreise hinter sich lassen, sich an unbeleuchtete Ufer wagen und das tödliche Spiel um Geräusch, Licht und Beute spielen.

---

## 2. Die Fangmechanik: Tag vs. Nacht & Schleier-Drill

Das Angeln in Shadowspore gliedert sich in zwei eng miteinander verzahnte Phasen, die den Tag-Nacht-Rhythmus des Spiels widerspiegeln.

```
      TAG (06:00 - 18:00)                    DÄMMERUNG & NACHT (18:00 - 06:00)
┌──────────────────────────────┐          ┌─────────────────────────────────────────┐
│ • Helle, ruhige Gewässer     │          │ • Wasser färbt sich tiefviolett         │
│ • Sichtbare Fischschwärme    │  ───►    │ • Leerenwirbel steigen aus Rissen auf   │
│ • Entspanntes Einholen       │          │ • "Licht vs. Scheu"-Dilemma             │
│ • Basisfische für den Kessel │          │ • Hohe Zerrkraft & Monster-Anlockung    │
└──────────────────────────────┘          └─────────────────────────────────────────┘
```

### 2.1 Normale Angelei am Tag (Meditation & Basisfänge)
* **Ablauf:** Der Spieler wählt über die Hotbar die Angelrute (`void_rod` / `hazel_rod`) aus. Durch Gedrückthalten der Aktionstaste (`InputManager`) wird die Wurfweite skaliert (angezeigt durch eine diskrete, kreisförmige Zielmarkierung im 16px-Raster auf der Wasseroberfläche).
* **Strömungs-Physik:** Nach dem Auftreffen driftet die Pose naturgetreu mit dem lokalen Strömungsfeld des Flusses (`WorldRivers.flow_at(point)`).
* **Fischschwärme:** Im Wasser sichtbare Schwärme (`shoal`, `brook` aus `data/river_animals.json`) reagieren auf den Köder. Nähert sich ein Fisch, beginnt die Pose sanft zu wippen.
* **Der Tag-Biss:** Ein klares, helles Plätschern, weißer Ringel-Shader-Effekt. Kurzes Bestätigen holt den Fisch ohne großen Widerstand an Land.
* **Ertrag:** Frische Silberforellen, Kieselgrundeln, Flusskrabben – solide Nahrung für die Grundrezepte am Kochkessel (`docs/cooking.md`).

### 2.2 Schleier-Angeln bei Dämmerung und Nacht (Tiefen-Ködern)
Sobald `TimeManager.night_amount() >= 0.3` erreicht, kippt die Gewässerökologie:
* Aus tiefen Flussbetten (`WorldRivers.is_deep(point)`) und den Becken der Seen (`lakes_baked.json`) steigen phosphoreszierende Schlieren empor. Die Fauna wechselt: Reiher und Enten schlafen im Schilf; aus dem Schlamm kriechen nachtaktive Schattenfische, Schleier-Aale und geisterhafte Tiefenwesen.
* Die Pose liegt nun in tintenschwarzem Wasser, das schwach in Türkis (`3cc0c6`) und Leeren-Violett (`6636ad`) glimmt.

### 2.3 Der Biss & Drill: Der Kampf gegen Strömung und Leere
Ein Schleier-Fang ist kein einfaches Reaktionsspiel, sondern ein physischer Zweikampf, der dem Spieler räumliches Taktieren und Feingefühl abverlangt:

1. **Das Antäuschen (Tiefen-Echos):**  
   Die Pose wird nicht sofort unter Wasser gerissen. Stattdessen tauchen dunkle Schattenwirbel darunter auf (gesteuert über `uniform vec4 disturbances[8]` im Wasser-Shader). Drei kurze, dumpfe Schläge im Controller/Audio kündigen das Wesen an.
2. **Der Anschlag:**  
   Genau im Moment des tiefen Abtauchens muss angeschlagen werden. Gelingt dies, rastet die Schnur ein und der **Drill** beginnt.
3. **Drill-Mechanik (Zerrkraft vs. Strömung):**  
   * **Die Zerrkraft:** Das gehakte Schattenwesen versucht, in tiefere Flusszonen, Strudel oder den nahen Weltrand zu flüchten.
   * **Winkel-Gegenhalten:** Über den linken Stick bzw. die Bewegungstasten (`InputManager.move_vector()`) muss der Angler den Hebelarm der Rute präzise im 90°-Winkel zur Zugrichtung des Fisches positionieren.
   * **Schnurspannung (Tension-Gauge):** Ein diskreter Bogen über der Spielerin zeigt die Schnurbelastung:
     - *Türkis (Gering):* Der Fisch hat Spielraum und flieht.
     - *Gold (Perfekt):* Maximale Erschöpfung des Fisches, Schnur hält.
     - *Magenta/Rot (Überlastung):* Schnurbruchgefahr! Schnur muss sofort freigegeben werden.
4. **Wasserunruhe & Monster-Anlockung (`Lockung`):**  
   * Gemäß `docs/nacht_monster_konzept.md` erzeugt Aktivität Reiz. Das heftige Schlagen des Tiefenwesens im Wasser und das Pfeifen der gespannten Sehne generieren kontinuierlich **Wasser-Unruhe** (`water_turmoil`).
   * Übersteigt der Drill 10–15 Sekunden, steigt der globale Reizwert der Gruppe rapide an. Krabbler (`ShadowSpider`) und Lauscher (`VoidListener`) in der Umgebung wittern die Unruhe und pirschen sich an das Flussufer heran!
   * Der Angler hört das Schaben von Spinnenbeinen auf dem Kies oder sieht herannahende rote Augenpaare im Dämmersaum.

### 2.4 Multiplayer-Zusammenspiel: Der Wächter & der Angler
Im Koop-Modus (1–4 Spieler) entfaltet das Schleier-Angeln seine stärkste Dynamik als asymmetrisches Teamspiel:
* **Der Angler** ist während des Drills vollkommen fokussiert, bewegungsgebunden und kann sein Schwert nicht ziehen.
* **Der/die Begleiter (Wächter)** sichern dem Angler den Rücken gegen aus dem Uferdickicht brechende Schattenkreaturen.
* **Das taktische Dilemma für Wächter:**  
  Tritt ein Begleiter mit gezogener Fackel oder Laterne zu nahe ans Wasser, um Monster abzuwehren, überflutet das Licht den Fangplatz – und verscheucht den scheuen Schattenfisch!
* **Kescher-Hilfe:** Ein zweiter Spieler kann sich ohne Licht mit einem Kescher am Ufersaum bereithalten. Trifft er das Erschöpfungs-Timing des Fisches, wird der Fang vorzeitig gelandet – bevor Schnurbruch oder Monster den Angler überwältigen.

---

## 3. Licht-Mechanik am Wasser: Das Licht-Dilemma

Das Grundaxiom von Shadowspore lautet: **„Licht ist Land“** (`TownRules.light_depth`). Doch am Wasser verkehrt sich dieser Schutz in ein spannungsgeladenes Risiko.

```
       LICHTKREIS DER BASIS / LATERNE                 DUNKLES, WILDES FLUSSUFER
┌─────────────────────────────────────────┐     ┌─────────────────────────────────────┐
│ • Sicher vor Schattenmonstern           │     │ • Extrem hohe Monster-Gefahr        │
│ • "Lichtdruck" schiebt Feinde weg       │ vs. │ • Schattenwesen pirschen heran      │
│ • Schattenfische MEIDEN diesen Bereich  │     │ • Scheue Tiefenwesen BEISSEN NUR    │
│ • Nur gewöhnliche Fische beißen         │     │   IN VOLLSTÄNDIGER DUNKELHEIT!      │
└─────────────────────────────────────────┘     └─────────────────────────────────────┘
```

### 3.1 Die Lichtscheu der Schattenfauna (`light_shyness`)
Jede Wasser- und Tiefenkreatur besitzt in `data/fishing.json` ein Attribut `light_shyness` (0.0 bis 1.0):
* **Lichtsucher (`light_shyness = 0.0`):** Gewöhnliche Tagfische und biolumineszente *Glimmer-Schmerlen*. Sie werden von schwachen Lichtquellen sogar angelockt.
* **Halbschatten-Wesen (`light_shyness = 0.5`):** Beißen im Dämmersaum der Stadt (am Rand der Laternenradien).
* **Reine Schattenkreaturen (`light_shyness = 1.0`):** Der legendäre *Schleier-Aal*, der *Tiefen-Zander* und alte Reliktkassetten. Sie existieren nur in absoluter Finsternis (`TownManager.light_depth(pos) < -32.0 px`). Fällt auch nur der Schein einer Fackel oder ein Scheinwerfer auf die Pose, taucht die Beute augenblicklich in die Tiefe ab.

### 3.2 Posen-Typen & Taktische Ausrüstung
Um dieses Dilemma zu meistern, fertigt der Spieler spezialisierte Posen und Ausrüstungen:

| Posen-Typ | Lichtabgabe | Eigenschaft & Funktion | Beute-Fokus |
|---|---|---|---|
| **Korkpose (Standard)** | Keine | Schwimmt neutral, driftet stark mit der Strömung. | Gewöhnliche Tagfische |
| **Glimmkappen-Pose** | Schwacher Schein (`NightLight`, 18px Radius, Türkis) | Zieht neugierige Lichtsucher an; Pose nachts exzellent lesbar. Schützt den Angler jedoch **nicht** vor Monstern. | Glimmer-Schmerle, Phosphor-Krabbe |
| **Obsidian-Pose (Dunkelpose)** | Absolut null Licht (`unshaded`, tiefviolette Silhouette) | Völlig unsichtbar im Trüben. Angler muss auf Audio-Feedback (Zupfen) und Rutenbiegung reagieren. Erfordert Fischen im Pechschwarz. | Schleier-Aal, Void-Polyp, Relikte |
| **Dämmerspiegel-Pose** | Phasenwechselnd | Schirmt das Licht nach unten ab: oben sichtbar für den Angler, nach unten in die Tiefe stockdunkel. | Seltene Übergangswesen |

### 3.3 Lockmittel & Leeren-Köder (Bait Crafting)
Köder werden im Inventar auf die Rute gesockelt und modifizieren Geruch, Geschmack und Lichtreflexe im Wasser:
1. **Glimmkappen-Spore (`glow_cap`):** Lockt pelagische Nachtfische an, beruhigt die Zerrkraft um 20%.
2. **Leerensplitter-Haken (`void_splinter`):** Schneidet durch turbulente Strömungen; zieht Wesen an, die vom Zerfall der Welt zehren.
3. **Schattengespinst-Made:** Gewonnen aus besiegten Schattenspinnen. Erzeugt einen unwiderstehlichen Duft für Tiefenräuber, erhöht jedoch die generierte Lockung bei Landmonstern um 50%.
4. **Bachminzen-Paste (`cooking` Derivat):** Dämpft die Wassergeräusche; reduziert den erzeugten Reizwert bei Monstern während des Drills drastisch.

---

## 4. Beute, Schatten-Kreaturen & Belohnungen

Die Belohnungen aus dem Schleier-Angeln sind eng mit den Hauptsystemen von Shadowspore verzahnt: Kochen (`cooking.md`), Skilltree (`skill_tree.md`), Ausrüstung und Alchemie.

### 4.1 Die Kreaturen der Tiefe
1. **Glimmer-Schmerle *(Glow Loach)* – Ungewöhnlich:** 14px lang, schlank, schimmert in zartem Türkis (`78f4e6`). Liefert *Glimmer-Galle* & *Zartes Schmerlenfilet*.
2. **Schleier-Aal *(Veil Eel)* – Selten:** 32px lang, pechschwarz mit pulsierenden violetten Adern (`8a4dff`). Nutzt Strömung voll aus. Liefert *Schleier-Haut* (Rüstungsmaterial) & *Trübes Leeren-Auge*.
3. **Abyssischer Zander *(Abyssal Pike)* – Episch:** Massiver Raubfisch mit knöchernem Schädelschild. Liefert *Panzerkamm* (für Schilde/Klingen) & *Reine Schatten-Essenz*.
4. **Lebender Schatten-Polyp *(Living Void Polyp)* – Gefahr!:** Wird er an Land gezogen, materialisiert er sich am Ufer als feindliche Mini-Kreatur mit Säurespritzern (`c21f3b`). Lässt wertvollen *Polypen-Nektar* fallen.
5. **Versunkene Schatulle der Vorfahren *(Sunken Reliquary)* – Schatz:** Fühlt sich an wie ein Hänger am Grund. Enthält seltene Erze aus den Tiefen der Mine (`mine.md`), antike Baupläne für Stadtlaternen, verlorene Tagebuchseiten.

### 4.2 Tiefe System-Verzahnung
* **Kochen am Kessel („Lies den Kessel“):**
  - *Schleier-Aal-Sud:* Verleiht 3 Minuten lang *Nachtsicht* (Sichtbarkeit von Augenpaaren am Bildschirmrand verdoppelt sich).
  - *Würzige Schmerlen-Pfanne:* Verleiht *Leeren-Resistenz* (mindert Kälteschaden in den tiefen Ebenen der Mine und Schatten-Schaden um 15%).
  - *Geistbrühe aus Polypennest:* Verleiht *Verstummen* (Schritte und Aktionen erzeugen 90 Sekunden lang keinen Reizwert bei Nachtmonstern).
* **Das Schleiergeflecht (`SkillTreeComponent`):**
  - Mystische Fänge liefern *Schleier-Essenzen* als Katalysatoren für Schatten-Knoten im Skilltree (*Tiefenohr*, *Schattenfaden*, *Nachtwandler-Aura*).

---

## 5. Mehrwert & Spielerlebnis

1. **Dynamischer Zeitdruck:** Die Nacht dauert exakt 4 Spielminuten (`TimeManager`). In der *Tiefen Nacht* steigen die seltensten Wesen auf – genau dann, wenn der Nacht-Direktor das höchste Monster-Budget ausschüttet.
2. **Sensorische Lesbarkeit statt UI-Balken:** Geschehen findet direkt auf der Wasseroberfläche statt (`disturbances[8]`, Rutenbiegung, Schnurspannung, Audio).
3. **Koop-Rollenverteilung:** Angler im Tunnelblick, Wächter auf Distanz mit Fackel/Schwert, Kescher-Assistent am Ufersaum.
4. **Sondernächte:** Leerenflut-Nächte und Nebelnächte verändern Gewässerbiologie und Sichtweiten drastisch.

---

## 6. Technische Umsetzung in Godot 4.7
* **Host-Autorität:** Der Server verwaltet die Zustandsmaschine (`FishingState`), validiert Uferpositionen und berechnet Drill-Physik.
* **Daten in JSON:** Vollständige Konfiguration in `res://data/fishing.json`.
* **Shader & Rendering:** Anbindung an `disturbances[8]` in `river_water.gdshader`.
* **Integration mit `NightDirector`:** Erzeugte Wasserunruhe (`turmoil`) speist direkt in das Spawnsystem von `NightDirector` ein.
