# Shadowspore 2.0 – Zonenwelt & Atlas (Konzept)

> **Stand:** Vollständig gebaut & integriert (2026-11-24). Gebaut: Atlas-Kern, Zonenlabor, Grenzen & Fernsicht, Stimmung & Ankommen, v2-Hauptwelt-Schnitt (`src/world/v2/zone_world.tscn`, `SaveGame.VERSION = 2`, `PocketSpace`-Migration, Löschung der v1-Testwelt), Hauptkontinent **ALTMARK** mit Website-Stil-Kartenmaler (`4 px/Tile`), spielbare Startzone **WINDKAP**, lebendiger 4-Ebenen-Atlas mit `16 px/Tile`-Match-Cut, Koop-Zonenstreaming (`ZoneCoop`) sowie `AtlasBook`, 8 Schleierfäden & zonenübergreifende Wegsteine (Schritte 1–10).
> **Gegenstand:** Systemarchitektur, Kontinent **ALTMARK** und Startzone **WINDKAP** als spielbare v2-Hauptwelt.
> **Baut auf:** der v2-Natur aus `tools/grass_lab.gd` (`GroundSurfaces`, `LivingGrass`, `LivingTree`, `RockyGround`, `WaterField`), dem Chunk-Streaming und `Jobs`, der Karte (`MapWindow`, `world_map.gdshader`, `map_veil.gdshaderinc`, `MapDiscovery`), den Wegsteinen, dem Wetter (`WeatherField`) und dem Nachtsystem. (Die frühere v1-Zonentestwelt `src/world/zones/` ist vollständig abgelöst und gelöscht.)

---

## 0. Die Idee in einem Absatz

Shadowspore 2.0 ist eine **Welt aus großen, offenen Zonen** wie in Lost Ark: jede Zone ist ein eigener Raum mit eigenem Thema, eigener Größe und eigener Stimmung, und sie wird für sich geladen. Anders als in Lost Ark sind die Zonen aber **Ausschnitte EINES echten Kontinents in echtem Maßstab**: Norden ist überall Norden, ein Fluss fließt über die Zonengrenze weiter, ein Gewitter zieht von einer Zone in die nächste, und vom Aussichtspunkt sieht man ins Nachbartal. Zwischen den Zonen liegt unbegehbares **Grenzland** (Grate, Waldmeere, Schluchten, Wasser), durch das nur **Schwellen** führen: Pässe, Furten, Brücken, Tunnel. Die meisten Schwellen sind **nahtlos**, es gibt keinen Ladebildschirm. Die Karte, der **Atlas**, ist eine einzige stufenlose Zoomfahrt von der Zone über den Kontinent bis zur ganzen Welt. Beim Öffnen steht man in der Zonenkarte, und die Karte ist **lebendig**: Tageslicht, Wolken, Regen und die Lichter der Stadt sind dieselben wie in der Welt.

---

## 1. Säulen

| Säule | Was sie bedeutet |
|---|---|
| **Eine Geografie** | Alles liegt in einem Koordinatensystem pro Kontinent. Zonen sind Fenster darauf, keine Inseln im Nichts. Daraus folgen Kompass, Sonne, Wetter, Flüsse, Fernsicht und die Karte fast von selbst. |
| **Offen, nicht linear** | Eine Zone ist ein Raum zum Herumstreifen, kein Schlauch. Mehrere Wege, Höhenzüge, Lichtungen, Geheimnisse abseits der Straße. |
| **Grenzen, die man versteht** | Keine unsichtbaren Wände. Man sieht immer, *warum* es nicht weitergeht: eine Klippe, ein Dickicht, reißendes Wasser, der Rand der Leere. |
| **Übergänge als Erlebnis** | Ein Pass ist ein Ort mit eigenem Moment (Nebel, Wind, ein Blick hinunter), kein Lade-Trigger. |
| **Die Karte gehört zur Welt** | Sie zeigt, was Ellie gesehen hat, so wie es gerade ist: Tag, Nacht, Wetter, Rauch, Lichter. Die Sprache bleibt die von Shadowspore: Ranken, Rinde, Schattenrauch für das Unbekannte. |
| **Baubar** | Pure Funktionen, Bakes, `Jobs`, host-autoritativ, strikt typisiert. Jede Stufe ist für sich testbar. |

---

## 2. Die Hierarchie der Welt

```
Welt (Atlas)
 └─ Kontinent            ein Koordinatensystem, eigener Bake (Relief, Küste, Grenzland)
     └─ Landstrich       Gruppe von Zonen mit gemeinsamem Thema (nur für Karte & Erzählung)
         └─ Zone         der geladene Spielraum
             ├─ Ort      benannter Teilbereich (Polygon): "Mühlenwiese", "Alter Steinbruch"
             ├─ Landmarke  Einzelobjekt mit Namen (Wegstein, Aussicht, Turm)
             └─ Tasche   Innenraum, Mine, Bossarena, Dungeon (eigener Raum, über einen Eingang)
```

- **Welt:** alle Kontinente, die Meere dazwischen und an ihrem Rand die Leere. Zuerst gibt es nur den Hauptkontinent. Die anderen werden nachgefüllt, auf der Weltkarte stehen sie als unkartierte Umrisse im Nebel.
- **Landstrich:** rein beschreibend (Name auf der Kontinentkarte, Musikfamilie, Wetterprofil). Beispiel: "Der Nebelwald" fasst drei Zonen zusammen.
- **Ort:** Lost Ark blendet beim Betreten den Namen des Teilgebiets ein. Das übernehmen wir: Orte haben Polygone, die Karte beschriftet sie ab einer Zoomstufe, und der HUD zeigt den Namen leise beim Betreten.
- **Tasche:** Das bisherige Taschenprinzip (`Interiors`, `MineManager`) bleibt, sein Platz wandert aber aus dem Kontinentbereich heraus (siehe 4.2).

---

## 3. Zonen

### 3.1 Zonentypen

| Typ | Beschreibung | Beispiele (nur zur Veranschaulichung) |
|---|---|---|
| **Feldzone** | Der Normalfall: offene Natur, Wege, Orte, Tiere, Nächte mit Schattenwesen. | Mühlenebene, Nebelwald-Saum |
| **Heimatzone** | Die Zone mit Glimmrast. Nur hier wird die Stadt gebaut (Stadtbau, Felder), hier greifen die Raids der Nacht. Kleine Außenposten (Lager, Wachfeuer) in anderen Zonen kommen später als eigener Schritt. | Valdrics Tal |
| **Siedlungszone** | Eine fremde Stadt mit vielen Bewohnern (Hallgrat). Dichte Wege, kaum Wildnis, eigene Nachtregeln. | Hallgrat am Glaskamm |
| **Passzone** | Klein und schmal, verbindet zwei große Zonen. Ein Erlebnis in sich: Hohlweg, Schlucht, Damm. | Der Graue Hohlweg |
| **Wunderzone** | Selten, klein, ein einziges großes Geheimnis oder ein Weltwunder. | Der Sternenkrater |
| **Küstenzone** | Hafen, Strand, Schiffsrouten zu anderen Kontinenten. | Südkap |
| **Leerenzone** | Vom Riss gezeichnet, die Leere frisst sich herein. Eigener Look, eigene Nächte. | Das Leerenblühen |

Taschen (Innenräume, Mine, Arenen, Dungeons) sind **keine** Zonen. Sie hängen an einer Zone und erscheinen auf deren Karte als Eingang.

### 3.2 Größenklassen

Grundlage ist das echte Tempo: Gehen 62 px/s (3,9 Tiles/s), Sprint 124 px/s (7,75 Tiles/s), der Reisetritt auf Straßen +8 %. Ein Bildschirm ist 40 × 22,5 Tiles. 1 Tile = 1 Meter (wie heute im Quest-HUD).

| Klasse | Kante (Tiles) | Bildschirme quer | Sprint quer | Wofür |
|---|---|---|---|---|
| **S** | 96–160 | 2,5–4 | 12–21 s | Pässe, Wunder, kleine Buchten |
| **M** | 160–256 | 4–6,5 | 21–33 s | Landstriche, Siedlungen |
| **L** | 256–384 | 6,5–10 | 33–50 s | große Feldzonen, Heimatzone |
| **XL** | 384–576 | 10–14 | 50–75 s | Hauptgebiete eines Kapitels (Hexenwald, Öde) |

Zonen sind nie rechteckig. Die Kante ist nur der umschließende Rahmen, die begehbare Fläche ist ein organisches Polygon (heute schon `ZoneBuilder.compute_zone_shape`). Da echte Wege 1,3- bis 1,6-mal länger sind als die Luftlinie, dauert eine XL-Zone zu Fuß gut zwei Minuten Sprint von Rand zu Rand. Das fühlt sich groß an, ohne leer zu sein.

**Dichteregel (Vorschlag):** Etwa alle 25–40 Sekunden normalen Gehens soll etwas passieren: ein Ort, eine Landmarke, ein Tier-Moment, ein Fund, ein Ausblick. Bei Gehtempo sind das etwa 100–150 Tiles. Die Regel prüft später ein Werkzeug (siehe 12.2).

### 3.3 Was jede Zone haben muss (Identitäts-Checkliste)

1. **Ein Leuchtturm:** eine Silhouette, die man von weitem sieht und an der man sich orientiert (eine alte Eiche, ein Turm, ein Felsdorn, ein Wasserfall).
2. **3–8 Orte** mit Namen und eigener Stimmung.
3. **Eine Signatur:** eine Pflanze, ein Tier oder ein Wetter, das es nur hier oder vor allem hier gibt.
4. **Ein Geheimnis** abseits des Weges (Rätsel, Versteck, Ruine).
5. **Ein Ausblick** in eine Nachbarzone (siehe 6.4, die Fernsicht).
6. **Ein Wegstein** oder ein bewusster Grund, warum es keinen gibt.
7. **Ein Nachtcharakter und ein Gefahrengrad:** welche Schattenwesen hier aus dem Dunkel steigen und wie, dazu RUHIG / RAU / WILD (siehe 6.6).
8. **Eine Stimmung:** Lichtgrad, Ambience, Musikfamilie, Wetterprofil (siehe 7).

### 3.4 Grenzen (wie eine Zone endet)

Jeder Abschnitt des Zonenrands hat eine **Grenzart**. Der Bake baut daraus echte Geometrie mit Kollision, kein Spieler stößt je gegen Luft.

| Grenzart | Im Spiel | Kollision |
|---|---|---|
| **Klippe** | Relief-Wand nach oben, zu steil zum Klettern | Relief-Kollision wie heute |
| **Abgrund** | Kante nach unten mit Blick in die Tiefe (Fernsicht!) | Kante, kein Ledge-Hop möglich |
| **Waldmeer** | ein Gürtel aus dicht stehenden Bäumen, Unterholz und Dornen, dahinter ein gebackenes Kronendach | Stämme und Dickicht |
| **Wasser** | See, Fluss oder Meer. Schwimmen geht ein Stück, dann drückt die Strömung zurück und die Ausdauer reicht nicht | tiefes Wasser + Strömung, ganz außen Kollision |
| **Gebirge** | Geröllhang und Felswand, die in gebackene Bergflanken übergeht | Relief |
| **Leerenrand** | die Leere frisst das Land (wie `VoidEdge` heute) | Void-Kollision |
| **Bauwerk** | Stadtmauer, verfallener Wall, Palisade | Bauwerk |

Regel: Die letzte unsichtbare Wand gibt es nur als Sicherheitsnetz, 3 Tiles hinter der sichtbaren Grenze.

### 3.5 Geplante Ränder und Übergänge (Leitlinie, 2026-11-23)

- **Nichts ist gerade.** Ränder und Übergänge werden von Hand geplant und gezeichnet. Ein Umriss besteht aus gesetzten Kontrollpunkten, die zu Kurven geglättet werden. Ihr Verlauf folgt der Landschaft (Waldkante, Hang, Bach), nicht einem Raster.
- **Gemeinsame Naht.** Die Grenze zwischen zwei Nachbarzonen wird **einmal** als Linie gezeichnet (`seams` im Kontinent), und beide Zonen übernehmen sie. Eine Schwelle ist ein Abschnitt dieser Naht (`seam` + `span`). Der Rest der Naht ist Grenze (meist Waldmeer, Hang oder Wasser).
- **Die Landschaft ist kontinentweit geplant, Zonen sind Ausschnitte.** Wälder, Lichtungen, Wege und markante Bäume liegen in `data/world/landscape/<kontinent>.json` in Kontinent-Tiles. Jede Zone baut nur, was in ihrem Bereich liegt. Ein Wald läuft deshalb über die Zonengrenze weiter, und auch der Übergang Wiese → Wald ist eine gezeichnete Kante mit Zungen, Vorposten und Lichtungen statt einer Linie an der Zonengrenze.
- **Nachbarn dürfen sich gleichen.** Nahe Zonen auf einem Kontinent haben oft dasselbe Biom oder ähnliche Biome. Was eine Zone ausmacht, sind ihre Orte, ihr Leuchtturm, ihre Signatur und ihre Stimmung (3.3), nicht ein Bruch im Boden. An einer Schwelle zwischen zwei gleichen Landschaften sieht man keine Grenze.
- **Schwellenmündung.** Zur Schwelle hin wird der Grenzgürtel lichter (weniger, jüngere Bäume, Wegränder). Man sieht die Öffnung von weitem, aber sie ist kein Schnitt.


---

## 4. Ein Kontinent, viele Bühnen: das Koordinatensystem

### 4.1 Echte Kontinentkoordinaten statt Slots ✅ entschieden

Die Testwelt legt jede Zone heute in einen Slot (`slot_index * 8192 px`). Festgelegt für 2.0 (2026-11-23): **Jede Zone liegt an ihrer echten Stelle auf dem Kontinent.** Eine Zone hat einen `origin` in Kontinent-Tiles. Ihre Weltkoordinaten sind Kontinentkoordinaten.

Was wir dadurch umsonst bekommen:

- **Kompass, Sonne und Schatten** stimmen zonenübergreifend (`SunShadows` arbeitet unverändert).
- **Wetter** wird einmal für den Kontinent gerechnet: `WeatherField` sampelt Kontinentkoordinaten. Ein Gewitter, das man in Zone A abziehen sieht, kommt in Zone B an, und die Karte zeigt die Front.
- **Nahtlose Schwellen:** Die Ränder zweier Nachbarzonen liegen tatsächlich nebeneinander. Sind beide geladen, läuft Ellie einfach hinüber (siehe 5).
- **Fernsicht:** Was hinter der Grenze liegt, liegt dort wirklich und kann als Hintergrund gezeichnet werden.
- **Die Karte** braucht keine Umrechnung: Zonenkarte, Kontinentkarte und Welt sind dieselbe Fläche in verschiedenen Maßstäben.
- **Koop:** Spieler in verschiedenen Zonen sind einfach weit voneinander entfernt. Abstand, Richtung und Kartenmarker sind echt.

**Größe und Genauigkeit:** Ein Hauptkontinent von etwa 2400 × 1800 Tiles misst 38 400 × 28 800 px. Bei dieser Größe ist ein float32 auf etwa 0,004 px genau. Das reicht für 2D-Physik und Pixelsnapping. Sprint quer über den Kontinent: gut 5 Minuten Luftlinie. Für weitere Kontinente gilt: Jeder Kontinent hat sein eigenes Koordinatensystem mit Nullpunkt an seiner Ecke. Ein Kontinentwechsel ist immer eine harte Reise (Schiff), es liegen nie zwei Kontinente gleichzeitig im Szenenbaum. So bleiben die Zahlen klein.

### 4.2 Wo die Taschen hinwandern

Innenräume liegen heute bei `POCKET_X0` 60 000 px. Das wäre mitten auf einem großen Kontinent. Festgelegt (mit Entscheidung 1): Alle Taschen ziehen in den **negativen Quadranten** (x < −16 000, y < −16 000). Dort liegt kein Kontinent. `Interiors.slot_at` und `MineManager` bekommen eine gemeinsame `PocketSpace`-Hilfe, die diesen Bereich verwaltet. Eine Tasche gehört logisch zu ihrer Zone (`parent_zone`), damit Karte, Wetter (keins), Nacht und Koop-Sichtbarkeit wissen, wo sie hingehört.

### 4.3 Die Koordinatenfragen an einer Stelle

Eine pure Klasse **`Atlas`** (RefCounted, aus den Daten gebaut, auf jedem Peer gleich) beantwortet:

| Frage | Methode |
|---|---|
| In welcher Zone liegt dieser Punkt? | `zone_at(continent, pos) -> StringName` (Zonenmaske, 4-Tile-Raster) |
| Ist er begehbar oder Grenzland? | `is_playable(pos)` |
| Welcher Ort? | `place_at(pos) -> StringName` |
| Welche Schwellen hat eine Zone? | `thresholds(zone)` |
| Wie komme ich von Zone A nach Zone B? | `route(from_zone, to_zone, flags) -> Array[Threshold]` (A* über den Schwellengraph, nur offene Schwellen) |
| Wo liegt das in Kartenkoordinaten? | `to_map(pos, level)` |
| Welcher Kontinent? Welche Tasche? | `continent_of(pos)`, `pocket_of(pos)` |

Die Testwelt-Klasse `ZoneCatalog` geht in `Atlas` auf. Ihre Voronoi-Aufteilung bleibt als Notlösung für Provinzen, die noch nicht von Hand entworfen sind.

---

## 5. Schwellen (Übergänge zwischen Zonen)

### 5.1 Arten

| Art | Übergang | Beispiel |
|---|---|---|
| **Pfad** | nahtlos | ein Weg durch eine Lücke im Waldmeer |
| **Pass** | nahtlos | Hohlweg zwischen zwei Graten, oben Nebel |
| **Furt / Brücke** | nahtlos | über den Fluss, der die Grenze bildet |
| **Tunnel / Höhle** | weich (kurzer Dunkelschnitt) | Felsentunnel, die Kanäle der Steinsetzer |
| **Sprung** | einseitig, nahtlos | Ledge-Hop in ein tieferes Tal, zurück nur außenherum |
| **Fähre / Boot** | hart (kleine Szene) | Seeufer, Überfahrt mit dem Fährmann |
| **Schiff** | hart (Reiseszene) | Hafen zu einem anderen Kontinent |
| **Wegstein** | hart (Lichtsprung) | Schnellreise, wie heute |

### 5.2 Nahtlos: wie es funktioniert ✅ entschieden

Pfad, Pass, Furt, Brücke und Sprung sind nahtlos, ohne Schnitt. Tunnel, Fähre, Schiff und Wegstein bleiben harte Übergänge.

1. **Ankündigung:** Nähert sich ein Spieler einer offenen Schwelle auf **48 Tiles**, beginnt der Host (und der Client des Spielers) die Nachbarzone vorzubereiten: Daten laden, die Chunks rund um das andere Ende der Schwelle bauen, alles als `Jobs` und mit niedriger Priorität.
2. **Brücke:** Ist die Nachbarzone bereit, sind beide Zonen für diesen Spieler geladen. Die Schwelle ist ein gewöhnliches Stück Gelände.
3. **Übertritt:** Überquert der Spieler die **Schwellenlinie**, wechselt seine Zone (`zone_id` auf dem Host, repliziert). Stimmung, Musik, Nachtsystem und Karte folgen. Es gibt keinen Schnitt.
4. **Nachlauf:** Die alte Zone bleibt geladen, solange der Spieler weniger als 64 Tiles von der Schwelle entfernt ist (Hysterese, kein Flackern beim Hin-und-her-Laufen). Danach wird sie entladen, falls niemand anderes sie braucht.

**Wenn das Laden zu langsam ist:** Jede nahtlose Schwelle ist so gebaut, dass sie eine **natürliche Maske** hat: ein Nebelband im Pass, ein dunkler Kronentunnel, eine Biegung im Hohlweg, ein Gischtschleier an der Furt. Ist die andere Seite beim Erreichen der Linie noch nicht fertig, wird der Nebel dichter, Ellie geht langsamer (wie im Sumpf), und die Kamera zieht sich sanft zurück. Das ist ein Moment und kein Ladebildschirm. Als Ziel gilt: Bei normalem Tempo darf das nie passieren. Die Abstände oben sind so gewählt, dass auch ein Sprint mit Burst (260 px/s) rund 3 Sekunden Vorlauf lässt.

**Daten einer Schwelle:**

```json
{
  "id": "hohlweg_nord",
  "kind": "pass",
  "a": {"zone": "muehlenebene", "line": [[812, 140], [826, 132]]},
  "b": {"zone": "nebelwald_saum", "line": [[812, 140], [826, 132]]},
  "mask": "fog",
  "open": {"flag": "hohlweg_frei"},
  "closed_reason": "Ein Felssturz versperrt den Hohlweg."
}
```

Da beide Seiten dieselben Kontinentkoordinaten haben, ist die Linie auf beiden Seiten dieselbe. `ZonePortal` aus der Testwelt wird zur Klasse `ZoneThreshold`. Die harten Arten nutzen die vorhandenen Abdeckungen: den Iris-Wipe der Türen (`door_wipe.gdshader`), die Lichtsäule der Wegsteine, eine kleine Fahrt im Boot.

### 5.3 Gesperrte Schwellen

Eine Schwelle, die die Geschichte noch nicht freigibt, ist **im Spiel sichtbar gesperrt**: ein Felssturz, eine eingestürzte Brücke, ein Wall aus Dornen der Leere, eine Wache. Die Karte zeigt die Schwelle mit einem Siegel und den Grund (`closed_reason`) im Tooltip. Gesperrt wird nur durch die Geschichte, nie durch die Stufe des Spielers.

---

## 6. Laufzeit

### 6.1 Bausteine

| Baustein | Aufgabe | Herkunft |
|---|---|---|
| **`Atlas`** (pure) | Daten und Geometriefragen (4.3) | aus `ZoneCatalog` |
| **`ZoneDirector`** (Node der Welt, Host entscheidet) | Wer ist in welcher Zone, was wird geladen, Schwellen, Vorbereitung, Entladen, Zonenwechsel-Signale | aus `ZoneWorld` |
| **`ZoneStage`** (eine pro geladener Zone) | Streamt die Chunks der Zone um die Spieler, baut die v2-Natur, hält Props, Wasser, Relief und `things` | aus `ZoneInstance` + Chunk-Streaming von `WorldLevel` |
| **`ZoneThreshold`** | eine Schwelle mit Linie, Maske, Sperre | aus `ZonePortal` |
| **`ZoneMood`** | Licht, Ambience, Musik, Wetterprofil, Nachtcharakter; blendet an Schwellen | neu, nutzt `DayNight`, `MusicDirector`, `WeatherManager` |
| **`ZoneBackdrop`** | Fernsicht hinter der Grenze | neu (6.4) |
| **`ZoneState`** | gespeicherter Zustand einer Zone + Aufholen beim Laden | aus `SaveGame` + `WorldLevel._thing_states` |
| **`PocketSpace`** | Taschen im negativen Quadranten | aus `Interiors` / `MineManager` |

### 6.2 Streaming in zwei Ebenen

- **Zonenebene:** Der `ZoneDirector` entscheidet, welche Zonen geladen sind. Das ist die Vereinigung aus allen Zonen, in denen ein Spieler steht, plus den Nachbarn, deren Schwelle angekündigt ist.
- **Chunkebene:** Innerhalb einer Zone streamt die `ZoneStage` 32×32-Tile-Chunks um die Spieler, genau wie `WorldLevel` heute: Phasen 0–4 als ein `Jobs`-Auftrag pro Chunk, Commit im Hauptthread im Frame-Budget. Eine XL-Zone ist also nie ganz im Speicher, nur der Teil um die Spieler.
- **v2-Felder:** `LivingGrass.recenter_field` und `WaterField.recenter_wave_field` folgen ohnehin dem Spieler (toroidaler Ringpuffer). Sie hängen deshalb am Spieler und nicht an der Zone. An einer nahtlosen Schwelle laufen sie einfach weiter.

### 6.3 Zustand und Aufholen

Jede Zone hat einen eigenen Speicherblock `zones.<id>`: `things` (Bäume, Steine, Büsche), Truhen, Rätsel, Entdeckung (Nebel), Orte, Chronik, `last_day`. Ist eine Zone nicht geladen, ist sie **eingefroren**. Beim Laden **holt sie auf**: alles, was heute schon in Tagen rechnet (Nachwachsen, Beeren, Stockausschlag, Felsen erholen sich, Feldfrüchte, Truhen), wird mit `heute − last_day` in einem Schritt nachgerechnet. Was eine pure Funktion der Uhr ist (Siedler, Karawane, Wetter, Tiere in ihrem Revier), braucht nichts.

Global bleiben: `TimeManager`, Wetter, Stadt (lebt in der Heimatzone, rechnet aber mit der Uhr), Quests, Haustiere (Reviere bekommen eine Zone).

### 6.4 Fernsicht

Hinter einer Grenze ist es heute schwarz. In 2.0 liegt dort, was wirklich dort ist:

- Jede Zone backt neben ihrer Kartenansicht eine **Fernsichttextur**: Kronendach, Felsflanken, Wasserflächen und Dächer als flaches, entsättigtes und ins Blaue verschobenes Bild in 1 px pro Tile (das ist Luftperspektive).
- Die `ZoneBackdrop` legt die Fernsicht der Nachbarzonen und des Grenzlands als Untergrund unter den Rand der eigenen Zone, gedimmt und mit Dunst. Kein Licht, keine Kollision, nur Bild.
- An **Aussichtspunkten** (`VistaPoint`, Wiesenbiom-Stufe 1) zieht die Kamera schon heute weit heraus. In 2.0 sieht man dabei ins Nachbartal: die Fernsicht samt Wolkenschatten und nachts den Lichtern der Siedlung dort.
- Am **Abgrund** wird die tiefere Zone unten im Bild gezeigt, deutlich dunkler und verschwommen.

Damit endet die Welt nie an einer Kante, und jede Zone kündigt ihre Nachbarn an.

### 6.5 Koop (Option B bleibt)

- Spieler dürfen in verschiedenen Zonen sein. Der Host simuliert jede Zone, in der ein Spieler steht.
- Jeder Spieler hat eine replizierte `zone_id`. Der Host setzt sie beim Übertritt.
- **Sichtbarkeit nach Zone:** Gegner, Tiere, Drops und Projektile einer Zone werden nur an Peers repliziert, die in dieser Zone oder an ihrer angekündigten Schwelle sind (`MultiplayerSynchronizer`-Sichtbarkeitsfilter). Das spart Bandbreite und verhindert Geisterobjekte.
- Ein Client lädt nur seine eigene Zone und deren angekündigte Nachbarn. Andere Spieler in fernen Zonen sind für ihn nur Punkte auf der Karte.
- **Zu einem Freund reisen:** Auf der Karte kann man einen Mitspieler anklicken und "ZU IHM" wählen. Ist ein Wegstein in seiner Zone erweckt, reist man dorthin. Sonst zeigt die Karte die Route über die Schwellen.
- **Kartenruf:** Ein Klick mit der mittleren Maustaste auf die Karte setzt für alle Mitspieler einen Ruf. Er erscheint auf deren Karte und in der Welt als kurzer Lichtstrahl, wenn sie in derselben Zone sind. Der Host leitet ihn weiter, nichts wird gespeichert.

### 6.6 Nacht, Raids und Tod

- Der `NightDirector` arbeitet pro besetzter Zone mit den Gruppen in dieser Zone. Budget-Regeln wie heute.
- Raids auf die Stadt gibt es nur, wenn jemand in der Heimatzone ist (wie `allow_raids_now()` heute).
- **Nachtcharakter pro Zone:** welche Arten, wie sie aufsteigen (Ufer, Waldboden, Ruinen, Leerenrisse), Sonderregeln (im Hexenwald: Nebel).
- **Schwierigkeit (entschieden: Mischung):** Die Grundstärke ist überall gleich und steigt wie heute mit der Nacht (Nachtnummer, Mond, Spielerstufe, `NightRules`). Dazu hat jede Zone einen **Gefahrengrad** als moderaten Aufschlag auf das Nachtsystem:

  | Grad | Nachtbudget | Elite-Chance | Rudelgröße |
  |---|---|---|---|
  | **RUHIG** | +0 % | +0 % | +0 % |
  | **RAU** | +20 % | +20 % | +20 % |
  | **WILD** | +40 % | +40 % | +40 % |

  Es gibt keine Levelsperren: Jede offene Zone ist betretbar. Der Grad wirkt nur auf die Nacht, nicht auf Tagesgegner oder Tiere. Er steht in `zone.json` (`danger`) und auf der Hover-Karte der Kontinentebene. Die Zahlen sind Startwerte und werden wie alles andere in `data/night.json` getunt.
- **Tod (entschieden):** Nach dem Prolog respawnt man standardmäßig an der Tür des Hauses in der Heimatzone. Wer einen Wegstein in der aktuellen Zone erweckt hat, wählt auf der Todeskarte zwischen ZUHAUSE und dem Wegstein. So zwingt eine ferne XL-Zone nicht zu langen Rückwegen. Während des Prologs gelten die bisherigen Regeln.

---

## 7. Stimmung pro Zone (`ZoneMood`)

Jede Zone trägt ein Stimmungsprofil, das an Schwellen über ungefähr 30 Tiles weich überblendet wird:

| Kanal | Inhalt | Anbindung |
|---|---|---|
| Licht | Farbgrad für Tag und Nacht, Sonnenstärke, Nebelgrundwert | `DayNight`, `MoodGrade`, `data/mood.json` |
| Wetter | Profil, das die Kontinentwetterkette moduliert (Küste neblig, Öde trocken, Hexenwald immer Dunst) | `WeatherManager` |
| Klang | Ambience-Bett für Tag und Nacht | `DayAmbience` |
| Musik | Familie und Motive, Vista-Mischung | `MusicDirector` |
| Wind | Grundwind, Böigkeit | `WorldWind` |
| Partikel | Pollen, Sporen, Asche, Gischt | `DayMotes`, `WorldWind`-Partikel |

Orte können das Profil leicht abwandeln (ein dunkler Hain innerhalb einer hellen Zone).

### 7.1 Ankommen in einer Zone

- **Erstes Betreten:** Eine große Einblendung oben in der Mitte. Der Zonenname erscheint in Gold (`PixelText`, doppelte Größe), darunter der Beiname. Daneben zeichnet sich in zwei Sekunden der Umriss der Zone mit Tinte, und ein Punkt markiert, wo Ellie hereinkommt. Danach welkt alles in Ranken weg. Leerenzonen schreiben ihren Namen in der Leerenschrift (`VoidTitle`).
- **Wiederkehr:** nur ein schmaler Schriftzug, 2 Sekunden.
- **Orte:** Beim Betreten eines Ortes taucht sein Name klein unter der Uhr auf, beim ersten Mal mit einem kleinen Stempel "ENTDECKT".
- Im Kampf, in Dialogen und in Story-Szenen wartet die Einblendung.

---

## 8. Erschließung & Chronik

### 8.1 Entdeckung

- **Nebel pro Zone:** eine Zelle pro 2×2 Tiles (feiner als heute, weil Zonen kleiner sind als die alte Welt). Der Host deckt um jeden Spieler auf, wie `MapDiscovery` heute. Gespeichert wird zstd-komprimiert im Zonenblock, und für Koop gibt es einen geteilten Snapshot.
- **Zonenstatus auf dem Kontinent:** *unbekannt* (Schattenrauch) → *gesichtet* (von einem Aussichtspunkt, aus der Ferne oder an einer Schwelle gesehen: Umriss und Name erscheinen) → *betreten* → *erschlossen x %*.
- **Weite Aufdeckung:** Aussichtspunkte und Wegsteine decken größere Kreise auf (heute schon `reveal_disc`). Auf dem Kontinent "sichten" sie Nachbarzonen.

### 8.2 Die Zonenchronik ✅ entschieden (entspricht dem Abenteuerbuch in Lost Ark)

Jede Zone hat eine Seite im **Atlasbuch**: erkundete Fläche, Orte, Wegsteine, Aussichtspunkte, Truhen, Rätsel, Flora- und Fauna-Einträge, Geheimnisse. Die Seite füllt sich von selbst aus Systemen, die es schon gibt.

**Schleierfäden** (entschieden). In jeder Zone sind 5–12 Schleierfäden versteckt: kleine, schimmernde Fäden aus Caelias Gewebe, an Orten, die man nur mit offenen Augen findet (unter einem Wasserfall, auf einem Dach, hinter einem Rätsel). Sie sind das Sammelgut, wie in Lost Ark die Mokoko-Samen, passen aber zur Geschichte: Jeder Faden nährt das *Ankerlicht*, das fünfte Siegel (storyboard 2.4), und auf der Weltkarte sieht man den Schleier sich schließen (9.5). Belohnungen bei 30/60/100 % pro Zone: kosmetisch und für die Karte (ein Kartenstempel, eine Rahmenranke, ein Titel), nie Macht.

---

## 9. Der Atlas: die neue Karte

### 9.1 Vier Maßstäbe, ein Zoom

Die Karte ist **ein stufenloser Zoom** über vier Ebenen. Mausrad, Q/E und der Zoomzweig bewegen eine einzige Zahl. Die Ebenen gehen ineinander über, es wird nicht umgeschaltet.

| Ebene | Maßstab (Bildschirm-px pro Tile) | Inhalt |
|---|---|---|
| **Ort** | 2,0–6,0 | Nahansicht: einzelne Bäume, Häuser, Pfadränder, Stadtplan. Nur in erkundeten Gebieten. |
| **Zone** *(Standard beim Öffnen)* | 0,6–2,0 | die ganze Zone gemalt, Orte beschriftet, Marker, Nebel, Spieler |
| **Kontinent** | 0,08–0,6 | alle Zonen mit Status, Grenzland, Landstriche, Schwellen, Wegsteine, Häfen, Routen, Mitspieler, Wetterfronten |
| **Welt** | < 0,08 | Kontinente, Meere, Strömungen, Seewege, die Leere am Weltrand, der Schleier |

Am linken Rand hängen die Ebenen als Namensanhänger (ORT / ZONE / KONTINENT / WELT). Ein Klick oder Tab/Umschalt+Tab fliegt zur nächsten Ebene: 0,6 Sekunden mit Ease-in-out und Zoom auf den Mauspunkt. Das Mausrad bleibt der Hauptweg.

### 9.2 Wie die Übergänge aussehen

- **Zone → Kontinent:** Beim Herauszoomen bleibt die eigene Zone scharf. Ab etwa 0,6 malen sich die Nachbarzonen von ihren Schwellen aus ein: eine geditherte Welle, die sich wie Tinte im Papier ausbreitet. Das Grenzland dazwischen erscheint als gemaltes Relief (Grate, Waldmeere). Ortsnamen verblassen, Zonennamen wachsen heran. Weil alle Ebenen dieselben Koordinaten haben, springt nichts.
- **Kontinent → Welt:** Man steigt **durch die Wolkendecke**. Eine Wolkenschicht aus dem echten `WeatherField` zieht mit eigener Parallaxe vorbei, für einen Moment ist nur Weiß und Grau zu sehen, dann liegt der Kontinent als Insel im Meer, Wellen und Strömungen bewegen sich, und am Rand frisst die Leere.
- **Hineinzoomen** läuft genau umgekehrt. Ein Doppelklick auf eine Zone fliegt in sie hinein, wenn sie betreten ist. Ist sie nur gesichtet, erscheint ihre Karte als Umriss mit Name und Grund.

### 9.3 Öffnen und Schließen: der Match-Cut

Die Karte öffnet **dort, wo das Bild gerade ist**:

1. M drücken. Für einen Frame wird das Spielbild als Textur gegriffen.
2. Die Karte startet bei genau dem Maßstab, in dem eine Kartenzelle einem Bildschirm-Tile entspricht (Ebene "Ort", 16 px pro Tile auf der Spielauflösung), zentriert auf Ellie. Spielbild und gemalte Karte liegen deckungsgleich übereinander.
3. Über 0,25 Sekunden geht das Spielbild in die gemalte Karte über. Bäume werden zu Kronen-Tupfen, Wege zu Linien, Ellie zu ihrem Marker.
4. Danach zoomt die Karte in 0,5 Sekunden weich auf die Zonenebene hinaus. Gleichzeitig weicht der Schattenrauch von Ellie zurück (wie heute) und die Ranken des Rahmens wachsen.
5. Schließen macht es schnell rückwärts (0,3 s): hinein zu Ellie, Übergang ins Spielbild.

Das Ergebnis: Die Welt *wird* zur Karte. Wer schnell hinschauen will, kann den Zoom-Teil mit einem zweiten Druck auf M oder einem Mausrad-Ruck abkürzen.

### 9.4 Die lebendige Zonenkarte

Die Zonenkarte ist ein gemaltes Bild mit lebendigen Schichten darüber, das per Kunstpixel im Shader gezeichnet wird (wie `world_map.gdshader` heute):

**Gebacken** (der Kartenmaler, 12.1):
- Höhen als Schummerung mit Licht von oben links (wie die ganze Pixelkunst) und Tuschlinien an den Kanten
- Untergrund: Gras, Erde, Stein, Sand, Moor in gedämpften Tönen aus der Spielpalette
- Wasser mit Tiefenstufen, Uferkante, Furten
- jeder Baum als Kronentupfen in seiner echten Größe und Farbe (Eiche, Birke, Tanne, Apfel), Wälder als dichtes Kronendach
- Wege und Straßen als Linien nach Rang (Trampelpfad, Weg, Straße mit Reisetritt)
- Gebäude als kleine Dächer mit Schatten, Ruinen als Mauerumrisse, Felsen als Punkte

**Lebendig** (pro Frame, alles kosmetisch):
- **Tageslicht:** Die Schummerung folgt der Sonne. Morgens liegen die Schatten im Westen, abends im Osten (`SunShadows.sun_cast`), zur goldenen Stunde wird die Karte warm.
- **Nacht:** mondblau. Siedlungslichter und Lagerfeuer glühen, die Lichtkreise der Stadt sind sichtbar (`TownManager.lit_circles()`), leuchtende Pflanzen und Kristalladern glimmen. Im Nebel öffnen sich wie heute Augenpaare.
- **Wetter:** echte Wolken aus `WeatherField` ziehen als Schatten und Schleier über die Karte, Regen erscheint als feine Schraffur, im Gewitter flackern Blitze. Man sieht, was kommt.
- **Wind:** Über offenen Wiesen laufen leise Wellen. Wasser glitzert.
- **Leben:** Rauch aus Kaminen, die Karawane auf ihrer Straße, Schwärme als kleine Flecken (nur aus geladenen Daten). Nichts davon verrät Gegner.
- **Unbekanntes:** der vorhandene Schattenrauch (`map_veil.gdshaderinc`) mit ausgefranster Kante.

### 9.5 Kontinent und Welt

- **Kontinent:** ein eigener Bake aus den heruntergerechneten Zonenkarten plus dem gemalten Grenzland. Zonen haben feine Grenzlinien, Landstriche große, gesperrte Zonen liegen unter einem Siegel. Schwellen erscheinen als kleine Torsymbole, Wegsteine als Statuen, Häfen mit gestrichelten Seewegen. Wetterfronten ziehen sichtbar über das Land. Mitspieler werden als Rautenmarker mit Namen angezeigt, auch in fernen Zonen.
- **Die Kontinentebene öffnet sich mit einem Story-Fund** (entschieden). Am Anfang hat Ellie nur die Zonenkarte (Ebenen Ort und Zone), und der Zoom endet am Zonenrand mit einer Ranke, die sich nicht weiter aufrollt. Ein Fund in der Geschichte schaltet Kontinent und Welt frei: Valdrics Ordenskarte oder eine Steinsetzer-Tafel. Welcher Fund und wann, entscheidet der Story-Entwurf. Beim Freischalten rollt sich die Karte einmal feierlich bis zur Weltebene auf.
- **Unbekannte Teile des Kontinents** (entschieden): Bevor Ellie eine Gegend selbst gesehen hat, zeigt die Karte dort eine **alte Steinsetzer-Gravur**. Das ist ein graviertes, einfarbiges Relief ohne Details und mit veralteten Namen. Erst Gesehenes wird farbig gemalt. Die Gravur kommt mit dem Fund, der die Kontinentebene öffnet. In der Zonenkarte bleibt Unbekanntes unter Schattenrauch.
- **Welt:** die Kontinente als Inseln, Meere mit Strömungen und Seewegen, die Leere am Weltrand. **Der Schleier** (entschieden, zur Geschichte): Auf der Weltebene liegt Caelias Gewebe als feines Netz aus Lichtfäden zwischen den Wegsteinen. Wo es zerrissen ist (der Große Riss, der Erste Riss), klaffen magenta Wunden. Jeder erweckte Wegstein, jeder Schleierfaden und jedes Siegel schließt sichtbar einen Teil. Die Weltkarte ist so der Fortschrittsanzeiger der Geschichte.

### 9.6 Marker: ein System für alles

Heute zeichnet `MapWindow` jeden Markertyp selbst (Quest, Tafel, Wegsteine, Haustiere, Hallgrat, Bosse, Spieler, Pins). In 2.0 gibt es **`MapMarkers`**, ein Register mit Anbietern:

```gdscript
## Jeder Anbieter liefert Einträge, das Register zeichnet, gruppiert und filtert.
{ "id": &"quest_main", "kind": &"quest", "pos": Vector2(...), "zone": &"muehlenebene",
  "levels": 0b0110, "priority": 90, "label": "SPRICH MIT GUSTAV", "anim": &"bloom" }
```

- **Ebenen:** Ein Marker sagt, auf welchen Ebenen er erscheint. Auf dem Kontinent werden Marker einer Zone gebündelt (ein Symbol mit Zahl), beim Hineinzoomen fächern sie auf.
- **Ziele in anderen Zonen:** Liegt ein Questziel in einer anderen Zone, zeigt die Zonenkarte am Rand **die Schwelle, die dorthin führt**, mit einem fließenden Pfeil. `Atlas.route` liefert sie. Auf dem Kontinent fließt eine goldene Tuschelinie durch die Schwellen bis zum Ziel. Damit weiß man immer, welcher Ausgang der richtige ist.
- **Filter:** Am unteren Zweig hängen Anhänger zum Ein- und Ausblenden (Quests, Wegsteine, Truhen und Rätsel, Natur, Mitspieler, eigene Pins).
- **Eigene Pins:** pro Zone, 4 Arten wie heute, dazu eine kurze Notiz. Lokal gespeichert.

### 9.7 Rahmen, Bedienung, Lesbarkeit

- **Rahmen:** Rankenstil wie heute. Oben hängt der Name der Zone mit ihrem Beinamen und dem Erschließungsgrad als kleiner Blüte. Rechts hängt eine **Ortsliste** (die Orte der Zone, unentdeckte als "???"), ein Klick fliegt hin. Links hängen die Ebenen, unten die Filter. Ein **Maßstabsbalken in Metern** und eine **Kompassrose** liegen unten rechts. Die Rose dreht sich beim Öffnen einmal ein.
- **Tasten:** M öffnen/schließen · Mausrad/Q/E zoomen · Ziehen oder WASD schwenken · Leertaste zu Ellie · Tab nächste Ebene · Rechtsklick Pin · Mittelklick Kartenruf · F Filter · Doppelklick hineinfliegen · Esc schließen. Gamepad: Sticks schwenken und zoomen, Schultertasten Ebenen, A wählen.
- **Hover-Karte** (Rindenpapier wie `ItemTooltip`) über einer Zone auf dem Kontinent: Name, Beiname, Typ, Größenklasse, Erschließung, Wegsteine, Wetter jetzt, Nachtlage (letzter Raid, Mond), Grund einer Sperre.
- **Reisen:** Die Wegstein-Reise (`WaystoneTravel`, `MapWaystones`) läuft im Atlas. Liegt das Ziel in einer anderen Zone, fliegt die Kamera über die Kontinentebene dorthin, eine Lichtspur folgt dem Schleier, und am Ziel endet die Fahrt mit dem Match-Cut ins Spielbild.

### 9.8 Was aus dem Bestehenden wird

| Heute | In 2.0 |
|---|---|
| `MapWindow` | bleibt die Hülle (Öffnen, Eingabe, Rahmen, Pins, Pause). Das Zeichnen übernimmt `AtlasView`. |
| `world_map.gdshader` | wird zum Zonen-/Ort-Shader mit neuen Eingängen (gemaltes Bild, Licht, Wetter). |
| `map_veil.gdshaderinc` | bleibt der gemeinsame Schattenrauch für alle Ebenen und den Fähigkeitsgraphen. |
| `ZoneMapView` (Testwelt) | geht in `AtlasView` auf. Ihre Kontinent-Rasterung dient als Platzhalter. |
| `MapDiscovery` | wird pro Zone geführt, dazu der Kontinentstatus. |
| `MapWaystones`, `MapPets`, `MapVistas`, `MapHallgrat`, Quest-/Tafel-/Boss-Zeichnung | werden Anbieter von `MapMarkers`. |

---

## 10. Reisen

| Netz | Was | Status |
|---|---|---|
| **Zu Fuß** | über die Schwellen, Straßen mit Reisetritt | Kern |
| **Wegsteine** | Schnellreise zwischen erweckten Statuen | vorhanden, wird zonenübergreifend |
| ~~Kanäle der Steinsetzer~~ | als zweites Reisenetz verworfen (2026-11-23). Schnellreise bleibt allein bei den Wegsteinen. | verworfen |
| **Fähren** | kurze Überfahrten über Seen und Flüsse innerhalb des Kontinents | Vorschlag |
| **Seewege** | Häfen zu anderen Kontinenten. Zuerst als Reiseszene, später vielleicht als echte Seezone. | später |

---

## 11. Daten

```
data/world/atlas.json                    Welt: Kontinente, Meere, Seewege, Schleier-Knoten
data/world/continents/<id>.json          Kontinent: Größe, Zonen-Origins, Landstriche, Grenzland, Häfen
data/world/landscape/<id>.json           Kontinentweite Landschaftsplanung (Wälder, Wege, Einzelbäume)
data/world/zones/<id>/zone.json          Zone: Kopf, Grenzarten, Schwellen, Orte, Landmarken, Stimmung, Nacht
data/world/zones/<id>/baked/...          Bakes (s. u.)
data/world/thresholds_<id>.json          alle Schwellen eines Kontinents (beide Seiten in einer Datei)
data/world/moods.json                    Stimmungsprofile pro Zone/Ort
```

**`zone.json` (Kopf, gekürzt):**

```json
{
  "id": "muehlenebene",
  "name": "MÜHLENEBENE",
  "subtitle": "Wo das Korn im Wind liegt",
  "continent": "main",
  "region": "gruenland",
  "kind": "field",
  "size_class": "L",
  "origin": [1180, 920],
  "size": [340, 300],
  "biomes": ["meadow"],
  "mood": "meadow_open",
  "night": "meadow_default",
  "danger": "rau",
  "unlock": {"flag": "town_founded"},
  "borders": [{"from": 0.00, "to": 0.18, "kind": "forest_sea"}, {"from": 0.18, "to": 0.40, "kind": "cliff"}],
  "places": [{"id": "alte_muehle", "name": "DIE ALTE MÜHLE", "poly": [[...]]}],
  "landmarks": [{"id": "muehle", "kind": "lighthouse", "pos": [1302, 1011]}]
}
```

**Bakes pro Zone** (alle aus einem Python-Bake wie heute, `py -3 tools/bake_zone.py <id>`):

| Datei | Inhalt |
|---|---|
| `height.png` | Höhenstufen und Rampen (wie `relief.png`, pro Zone) |
| `surface.png` | Untergrundart pro Tile für `GroundSurfaces` |
| `water.png` | Tiefe und Strömung für `WaterField` |
| `mask.png` | begehbar / Grenzland / Grenzart / Ort-Index |
| `paths.json` | Wegenetz mit Rang |
| `props.json` | handgesetzte Props, Bereiche für die Füllung |
| `map.png` | das gemalte Kartenbild (4 px pro Tile, `tools/paint_zone_map.py`, für scharfen `ORT`-Zoom `2–6 px/Tile` & `16 px/Tile` Match-Cut) |
| `map_light.png` | Normalen und Höhe für das Tageslicht auf der Karte (4 px pro Tile) |
| `far.png` | die Fernsicht-Küstensilhouette / Kronenmeer (4 px pro Tile, 6.4) |

**Saves (`SaveGame.VERSION = 2`):** `zones.<id>` pro Zone (6.3), dazu `atlas` (Kontinentstatus, Chronik, Schleierfäden, Pins) und `player.zone`. Die Position wird in Kontinent-Tiles gespeichert, die Zone ist daraus ableitbar. Ältere v1-Spielstände (`version < 2`, `WorldLevel`) werden abgelehnt, sodass v1-Saves beim Start frisch am Küstenlager in `WINDKAP` beginnen.

---

## 12. Werkzeuge

### 12.1 Der Kartenmaler

`py -3 tools/paint_zone_map.py <id>` macht aus den Zonen-Bakes das gemalte `map.png`: Schummerung, gedämpfte Palette, Kronentupfen aus den echten Baumpositionen der Füllung, Wege nach Rang, Dächer, Tuschkanten, Ufer. Daneben schreibt er `map_light.png` und `far.png`. Der Kontinent-Maler setzt die Zonenbilder zusammen und malt das Grenzland. **Grundsatz:** Die Karte wird aus denselben Daten gemalt, aus denen die Welt gebaut ist. Sie lügt nie.

### 12.2 Prüfwerkzeuge

- `tools/check_zone.py <id>`: Ist jede Stelle von jeder Schwelle aus erreichbar? Hat jeder Randabschnitt eine Grenzart? Wie lang ist die längste Strecke ohne Ort oder Landmarke (Dichteregel)? Passen Größe und Klasse zusammen?
- `tools/check_atlas.py`: Liegen Schwellen auf beiden Seiten gleich? Ist jede Zone über den Graph erreichbar? Gibt es Überlappungen? Fließt Wasser über Grenzen bergab?
- `tools/test_zone_director.tscn`: laden, entladen, nahtloser Übertritt, Hysterese, Aufholen, Koop-Sichtbarkeit (zwei Prozesse, eigener Loopback-Port).
- `tools/test_atlas_view.tscn` und `tools/preview_atlas.tscn -- --dir=/abs --level=zone|continent|world [--time=..] [--weather=..] [--open]`: Captures aller Ebenen, Übergänge und des Match-Cuts.

---

## 13. Bau-Reihenfolge

| Schritt | Inhalt | Ergebnis |
|---|---|---|
| **1. Entscheidungen** | die offenen Punkte aus 14 | Freigabe |
| **2. Atlas-Kern** ✅ gebaut (2026-11-23, siehe 13.1) | Datenformat, `Atlas` (pure), Kontinentkoordinaten, `PocketSpace`, Tests | Koordinatenfragen beantwortet |
| **3. Zonenlabor** ✅ gebaut (2026-11-23, siehe 13.2) | `ZoneDirector` + `ZoneStage` mit Chunk-Streaming und v2-Natur. Zwei kleine Testzonen (`labor_wiese` ↔ `labor_wald`), eine nahtlose Schwelle, Speichern pro Zone, Aufholen | man läuft ohne Schnitt von Zone zu Zone |
| **4. Grenzen & Fernsicht** ✅ gebaut (2026-11-23, siehe 13.4) | Nähte, geplante Landschaft, Waldgürtel, `ZoneBackdrop`, Schleier bei langsamem Laden | die Welt endet nie an einer Kante |
| **5. Stimmung & Ankommen** ✅ gebaut (2026-11-23, siehe 13.5) | `ZoneMood` mit Überblendung, Zonen- und Ortseinblendung | jede Zone fühlt sich anders an |
| **5b. Hauptwelt-Schnitt (M1)** ✅ gebaut (2026-11-23) | v2 `ZoneWorld` (`src/world/v2/zone_world.tscn`), `GameLauncher`/`MainMenu`/`PauseMenu` ohne `WorldLevel`-Fallback, `SaveGame.VERSION = 2`, `PocketSpace`-Migration (`Interiors`, `MineManager`, `StarHallRoom`), Löschung von `src/world/zones/`, Isolierung von `labor_wiese`↔`labor_wald` in `"lab"` | v2 ist die alleinige Hauptwelt |
| **6. Atlas I: Zonenkarte** ✅ gebaut (2026-11-24, siehe 13.6) | `4 px/Tile` Kartenmaler (`paint_zone_map.py`), `AtlasView` Zone/Ort, `2×2`-Nebel pro Zone, `MapMarkers`, `16 px/Tile` Match-Cut | die neue Karte im Spiel |
| **7. Atlas II: Kontinent & Welt** ✅ gebaut (2026-11-24, siehe 13.6) | Kontinentbake (**ALTMARK**-Gravur + Schären), stufenloser Zoom, Wolkendurchstieg, Routen über Schwellen, Hover-Karten | der ganze Atlas |
| **8. Lebendige Karte** ✅ gebaut (2026-11-24, siehe 13.6) | Tageslicht, Nacht, Wetter, Wind, Rauch & Caelias Schleier auf der Karte | "die Karte lebt" |
| **9. Koop** ✅ gebaut (2026-11-24, siehe 13.6) | Pro-Peer-Zonenstreaming, Sichtbarkeit nach Zone/`PocketSpace`, zum Freund reisen ("ZU IHM"), Kartenruf (`MapPingPillar`), 2-Prozess-Netzwerktest (`test_zone_director.tscn`) | 1–4 Spieler verteilt |
| **10. Reisen & Chronik** ✅ gebaut (2026-11-24, siehe 13.6) | **WINDKAP** spielbar, Wegsteine zonenübergreifend, Wegstein-Respawn, `AtlasBook` (`30%/60%/100%`), 8 Schleierfäden (`VeilThreads`), Steinsetzer-Kartentafel (Kontinentebene + Gravur) | Erschließung als Spielziel |

Schritte 3–5 und 6–8 können parallel laufen, sobald Schritt 2 steht: Die Karte braucht nur den `Atlas` und Bakes, keine laufende Zone.

### 13.1 Was Schritt 2 gebaut hat

- **Daten** unter `data/world/`:
  - `atlas.json` listet die Kontinente mit ihrer Lage auf der Weltkarte (`chart`).
  - `continents/main.json` beschreibt den Hauptkontinent **ALTMARK** (2400 × 1800 Tiles, 5 Landstriche, ~11 Zonen-Polygone, Nähte, Verweis auf `thresholds_main.json` und `landscape/main.json`).
  - `continents/lab.json`, `thresholds_lab.json` und `landscape/lab.json` isolieren die beiden S-Testzonen `labor_wiese` und `labor_wald` mit der nahtlosen Schwelle `labor_kronengang` als eigenständige `"lab"`-Testfixture für `tools/zone_lab.tscn` und `tools/test_zone_lab.tscn`.
  - `thresholds_<id>.json` enthält die Schwellen eines Kontinents. Eine Linie gilt für beide Seiten gemeinsam, `kind`, `one_way` und `open.flag` stehen pro Schwelle.
  - `zones/<id>/zone.json` beschreibt je eine Zone. Umriss, Orte und Landmarken stehen in Tiles relativ zu `origin`, der Atlas verschiebt sie beim Laden.
- **`DataRegistry.json(rel_path)`** lädt und cacht verschachtelte JSON-Dateien unter `res://data/`, denn `table()` liest nur die oberste Ebene. `forget_json()` leert den Cache.
- **`Atlas`** (src/world/atlas.gd) ist pure, unveränderlich nach dem Bau und auf Workern sicher.
  - Laden und Bauen: `shared()`, `from_data()`.
  - Abfragen: `zone_at`, `zone_at_tile` (Bucket-Raster aus 64 Tiles + Punkt-in-Polygon, etwa 1,5 µs pro Abfrage), `is_playable`, `place_at`, `thresholds_of`, `is_threshold_open`, `is_zone_open`, `crossed` (ob ein Schritt die Linie gekreuzt hat), `route`/`reachable` (Dijkstra über offene Schwellen, Einbahnsprünge, Startpunkt), `danger_scale` (RUHIG 1,0 / RAU 1,2 / WILD 1,4), `size_class_for`.
  - Datenfehler werden in `problems` gesammelt, der Bau bricht nicht ab: unbekannter Kontinent, unbekannte Art oder unbekannter Gefahrengrad, Größenklasse passt nicht zur Größe, Umriss größer als `size`, Zone ragt über den Kontinent, überlappende Zonen, Orte oder Landmarken außerhalb, doppelte IDs, eine nahtlose Schwellenlinie nicht am Rand beider Zonen, Schwelle zu einer unbekannten Zone oder zu sich selbst, Kontinentwechsel ohne Schiff, Zone ohne Schwelle.
- **`PocketSpace`** (src/world/pocket_space.gd) legt alle Taschen strikt in den negativen Quadranten (`x, y < -16 000`): ROOM (64 × 1600 px, `[-80000, -54400) × [-80000, -73600)`) für `Interiors` (mit 2×2-Block `[17, 18, 33, 34]` für `personalraum` + Flure) und LARGE (36 × 5600 px, `9×4`, `[-80000, -29600) × [-56000, -33600)`) für `MineManager` (Ebenen `1..32` in Slots `0..31`) sowie `starhall` / Caelias Kosmos (Slot `35`). Abfragen: `slot_origin`, `slot_rect`, `locate`, `is_pocket`, `register_pocket`, `parent_zone_at`. `Interiors`, `MineManager`, `ZeroGComponent` und `StarHallRoom` sind vollständig umgestellt.
- **Test** `tools/test_atlas.tscn` (headless, `ATLAS OK`): Fixtures für Abfragen, Routen und jeden Datenfehler, die erweiterten Taschenplätze (`64 + 36`), die echten Daten in `data/world/` (`"main"` & `"lab"`) und Abfragen über `Jobs.parallel_for`. Die alte v1-Zonentestwelt (`test_zones.tscn` / `src/world/zones/`) wurde entfernt.

### 13.2 Was Schritt 3 gebaut hat (Zonenlabor)

- **`ZoneStage`** (src/world/v2/zone_stage.gd) ist eine geladene Zone an ihren echten Kontinentkoordinaten.
  - `ZoneStage.build(atlas, zone, tileset, material, saved)` baut sie **abseits des Szenenbaums**, auf einem `Jobs`-Worker. Eine S-Zone braucht dafür etwa 2–4 s.
  - Gebaut werden: Bodenkacheln (der Umriss plus 4 Tiles Grenzland, jede Grenzland-Zelle gehört genau der nächstgelegenen Zone), `GroundSurfaces` (Wald, Wege, Moos, Senken, Wurzelzonen der Bäume), `LivingGrass` (nur innerhalb des Umrisses, über `grass_habitat_at`), `LivingTree`s und Kollision am Umriss.
  - An einer nahtlosen Schwelle ist der Umriss offen. Dort liegt stattdessen ein **Tor** (`set_gate`), das der Director schließt, solange die Nachbarzone fehlt.
  - Auf dem Hauptthread folgen `attach()` (Boden hochladen, `Terrain.register_layer`), `export_state()` (Baumzustände nach Knotennamen `T<n>`), `apply_state()` (für Clients) und `catch_up(days)`.
  - `catch_up` holt die verpassten Tage nach: ein Wachstumsschritt pro `grow_days` der aktuellen Stufe, Stümpfe nach `coppice_days` (Standard 3).
- **Inhalt aus Daten:** Der Block `nature` in `zone.json` enthält `seed`, `meadow`, `turf` {accents, kinds}, `forest`, `ways` [{kind, pts, seed, damp, abs}], `moss`/`hollows` [cx, cy, rx, ry], `trees` und `scatter` [{species, count, stages, seed, gap, edge, way_gap}].
  - Ein Weg über eine Schwelle steht mit `abs: true` (Kontinent-Tiles) und gleichem Seed in **beiden** Zonen. Beide malen ihn dadurch deckungsgleich in den gemeinsamen Nahtstreifen.
  - `scatter` ist deterministisch: Jeder Peer baut dieselben Bäume unter denselben Namen.
- **`ZoneDirector`** (src/world/v2/zone_director.gd) streamt die Zonen eines Kontinents.
  - Jeder Peer streamt um **alle** Spieler, wie die Chunks der alten Welt. So hat jeder Peer dieselben Zonen, und die RPCs der Bäume finden ihr Ziel.
  - Eine Zone lädt, wenn ein Spieler auf 48 Tiles an ihren Umriss herankommt, und bleibt bis 64 Tiles geladen.
  - Es baut immer nur eine Zone zur Zeit. `Terrain.patches` wird nur geändert, solange kein Bau läuft, denn `LivingGrass` liest die Liste auf dem Worker.
  - Die Startzone baut `load_now()` synchron.
  - Der Host legt die Zone jedes Spielers fest (`player_zone`, Signal `zone_changed`, RPC an alle). Das Grenzland behält die letzte Zone.
  - Eine Schwelle ist offen, wenn beide Seiten geladen sind und `Atlas.is_threshold_open` (Story-Flagge über `flags_source`) zustimmt.
  - Beim Entladen merkt sich der Host `{trees, day}`. Beim nächsten Laden kommt `catch_up(heute − day)`.
  - `export_state`/`import_state` ergeben den Speicherblock `{version, zones}`. Ein Client fragt den Host beim Anhängen nach dem Live-Zustand der Zone (`_rpc_request_zone`).
- **Platzhalter-Inhalt:** Die LABORWIESE (Blumenteppiche, Alte Eiche, Wildäpfel, Birken) und der LABORWALD (Waldboden ab 10 Tiles hinter der Naht, 24 Eichen, 12 Birken, Moosgrund) sind über den Pfad am Kronengang verbunden.
- **Laborszene** `tools/zone_lab.tscn` (erweitert test_level.gd, Gruppe `sandbox`):
  - Start in der Wiese, `-- --at=x,y` startet an anderen Tiles, `-- --continue` lädt `user://zone_lab.json`.
  - F7 schaltet auf den nächsten Tag, F8 speichert.
  - Eine Statuszeile zeigt Zone, Gefahrengrad, Tile, Tag, geladene Zonen und den Zustand der Schwelle.
- **Test** `tools/test_zone_lab.tscn` (headless, Ausgabe `ZONE LAB OK`) prüft:
  - gleicher Bau zweimal, Bäume im Umriss, Gras nur im Umriss, keine doppelten Bodenkacheln
  - Startzone sofort da, Wald noch nicht
  - Rand blockiert, Schwelle zu
  - Wald streamt beim Herankommen, die längste Frame-Zeit wird gemessen
  - Schwelle offen, Naht begehbar, Übergabe an die Waldzone
  - Wald entlädt mit dem gefällten Baum
  - Rückkehr nach 7 Tagen: Stumpf holt auf
  - Speicherblock-Rundreise
- **Noch nicht** (spätere Schritte): Grenzland-Geometrie und Fernsicht (Schritt 4), `ZoneMood` (5), Netzwerktest mit zwei Prozessen (9); der `SaveGame`-Speicherblock (`SaveGame.VERSION = 2`), Bäume und Boden auf mehreren Frames sind erledigt (siehe Messung).
- **Anhängen in Scheiben (2026-11-23):** Gemessen kostete das Anhängen in einem Stück 66–105 ms. Das lag an zwei Dingen: Die Bodenkachel-Ebene baut 20 000 Kacheln auf einmal am Frame-Ende (~31 ms), und der erste Baum jeder Art und Stufe lädt sein Sprite-Blatt (bis zu 32 ms). Jetzt gilt:
  - Der Worker berechnet die Kacheln nur noch (`_cells`), gesetzt werden sie in Portionen von 2400 pro Frame.
  - Die Baum-Blätter (`ZoneStage.sheet_paths`) lädt `Jobs.request_warm` schon während des Baus im Hintergrund.
  - `attach_step(deadline)` hängt Boden-Upload, Kacheln, Blätter und dann die Bäume mit 4 ms Budget pro Frame an. Die Zone gilt erst als geladen (Schwelle offen, Aufholen), wenn alles da ist.
  - Gemessen (headless): LABORWALD 4,9 s Bau, 15 Anhänge-Frames, längster Abschnitt 4,5 ms, längster Frame während Bau und Anhängen 11,3 ms. Die Startzone hängt `load_now` in einem Stück an (~190 ms, beim Spielstart).
- Sichtprüfung `zone_lab.tscn -- --at=1146,966 --capture=/abs.png`: Pfad ohne Bruch über die Naht, Waldboden beginnt hinter der Schwelle.

### 13.3 Plan für Schritt 4 (Grenzen & Fernsicht)

So war es geplant; was gebaut wurde und wo es abweicht, steht in 13.4.

1. **Nähte im Atlas:** `seams` im Kontinent (handgezeichnete Polylinien zwischen zwei Zonen). Zonen-Umrisse dürfen `{"seam": id}` einfügen, die übrigen Kontrollpunkte werden zu Kurven (Catmull-Rom) geglättet. Schwellen liegen auf einer Naht (`seam`, `span` [von, bis] als Anteil der Länge) und werden zu einer Polylinie (`line`).
2. **Landschaft:** `data/world/landscape/main.json` mit Wäldern (Umriss, Arten, Dichte), Wegen und Einzelbäumen in Kontinent-Tiles, gelesen über eine pure Klasse `Landscape`. `ZoneStage` malt Waldboden aus einer Maske pro Tile (`GroundSurfaces.paint_forest_mask`) und setzt die Bäume, die in ihrem Bereich stehen.
3. **Grenzgürtel (Waldmeer):** Die pure Klasse `ZoneBorders` erzeugt deterministisch einen inneren Gürtel (begehbar, echte Bäume) und einen äußeren Gürtel außerhalb des Umrisses (Bäume ohne Interaktion). Zur Schwellenmündung wird er lichter. Jede Zone nimmt nur die Bäume, die ihr gehören, so stehen an einer Naht nie zwei Bäume übereinander. Kollision: ein Ring 2 Tiles außerhalb, ohne die Teile in anderen Zonen, dazu die geschlossenen Teile der Naht und das Tor auf der Schwelle.
4. **Fernsicht `ZoneBackdrop`:** ein dunkles Kronenmeer mit Luftperspektive hinter dem Gürtel (Shader, Welt-Koordinaten, Wind) und ein Nebelschleier über einer Schwelle, deren Nachbar noch fehlt.

### 13.4 Was Schritt 4 gebaut hat (Grenzen & Fernsicht)

Leitlinie 3.5 gilt: Ränder und Übergänge sind von Hand geplant, nie gerade, und Nachbarzonen dürfen sich ähneln (die LABORWIESE trägt Zungen des Kronenwalds, eine Birkeninsel und eine Apfelwiese).

- **Nähte** (`Atlas.Seam`, Kontinent `seams`): eine von Hand gezeichnete Linie, die beide Nachbarn mit `{"seam": id}` in ihren Umriss einfügen. Der Atlas findet die Richtung selbst. Mit `"curve": true` werden die übrigen Kontrollpunkte zu einer Kurve (Catmull-Rom, alle 1,5 Tiles ein Punkt), die Naht bleibt wie gezeichnet. Eine Schwelle mit `seam` + `span` [von, bis] ist dieses Stück der Naht (`Threshold.line`, eine Polylinie). `Atlas.point_along`, `polyline_length`, `sub_polyline`, `smooth_closed`, `smooth_open`.
- **Landschaft** (`Landscape`, src/world/v2/landscape.gd, Datei `data/world/landscape/main.json`, vom Kontinent über `landscape` benannt): kontinentweit geplant, rein und unveränderlich, `Landscape.of` einmal auf dem Hauptthread (im `ZoneDirector.setup`), Worker lesen nur.
  - `stands`: Wälder, Haine, Obstwiesen mit Umriss (Kurve), Lichtungen (`glades`), Artenmischung `mix` [{species, w, stages}], `spacing`, `edge` (zum Rand und zu Lichtungen hin lichter und jünger), `soil` (Waldboden), `seed`. Die Bäume stehen auf einem Raster mit Zufall pro Zelle, also verschiebt eine geänderte Kontur die übrigen Bäume nicht.
  - `ways`, `moss`, `hollows`, `trees` (Einzelbäume), `turf.forest` (Bodenakzente unter Waldboden).
  - **Waldgürtel** aus `borders` jeder Zone (`forest_sea`, `depth`, optional `mix`): Reihen entlang des Umrisses von `depth` Tiles innen bis 3,4 Tiles außen, innen jung und licht, am Rand alt und dicht. An der Mündung einer nahtlosen Schwelle wird der Gürtel lichter und hört 2,2 Tiles davor auf (auch für Wälder). Kein Baum auf einem Weg (2,6 Tiles), keiner doppelt.
  - Jeder Baum gehört genau einer Zone: der, in der er steht, sonst der nächsten (Grenzland). `trees_of(zone)` gibt die Reihenfolge und damit die Knotennamen `T<n>`.
- **Waldboden auf der GPU** (`GroundSurfaces.set_forest_mask`): Die Zone baut eine Maske (ein Texel pro Tile, geplante Wälder mit `soil` plus eine weiche Scheibe um jeden Gürtelbaum, zweimal geglättet). Der Shader `ground_surfaces.gdshader` liest Maske und eine kachelbare Rauschtextur (Kante, Moos, Schatten) und legt den Humus selbst. `_forest_cell` rechnet auf der CPU genau dasselbe für Schritte (`surface_at`) und Gras (`grass_habitat_at`). Pro Zelle wird nichts mehr gemalt, das spart beim Wald 1,7 s Bauzeit und skaliert auf große Zonen.
- **Kollision:** Der Umriss wird in 1-Tile-Stücke zerlegt, offen bleibt nur, was auf einer nahtlosen Schwellenlinie liegt. Alle geschlossenen Stücke sind ein `ConcavePolygonShape2D`. Das Tor einer Schwelle ist ihre ganze Linie. Die geschlossenen Teile einer Naht sind in beiden Zonen Wand.
- **Fernsicht `ZoneBackdrop`** (src/world/v2/zone_backdrop.gd + `zone_backdrop.gdshader`): ein Kronenmeer bis 26 Tiles hinaus, ab 1,6 Tiles hinter dem Umriss, geschlossen ab 4,2, mit Dunst zur Ferne hin. Eine Chamfer-Distanz mit Zonen-Etiketten gibt jedem Tile seinen Abstand und seine nächste Zone; jede Zone zeichnet nur ihren Teil. Ganze Kronen erscheinen nach der Maske in ihrer Mitte, so endet das Meer nie an einer Linie. Kronen in Welt-Koordinaten, Licht von oben links, ein Pixel Wind, weltbeleuchtet (Nacht über `CanvasModulate`).
- **Schleier `ZoneVeil`** (+ `zone_veil.gdshader`): dunkler, treibender Nebel über der Mündung einer geschlossenen Schwelle, 5 Tiles zum Nachbarn hin. `ZoneStage.set_gate` blendet ihn in 1,6 s ein oder aus.
- **Bäume im Wald sparsam:** `LivingTree` schiebt die Nässe nur noch an die Materialien, wenn sie sich ändert. Vorher setzte jeder Baum in jedem Frame die Parameter aller Kronen-Cluster, an der Naht kostete das ~17 ms pro Frame. Gras-Abfragen finden Baumzonen in 128-px-Eimern ohne Liste pro Abfrage.
- **Gemessen (headless):** Landschaft planen 114 ms. LABORWALD: 376 Bäume, Bau ~6 s auf dem Worker (Gras 3,7 s, Oberfläche 1,5 s), Anhängen in ~80 Frames, längster Abschnitt 5 ms. LABORWIESE: 182 Bäume. Pro Bauphase stehen die Zeiten in `ZoneStage.build_ms`.
- **Tests:** `tools/test_zone_lab.tscn` (`ZONE LAB OK`, 45 Prüfungen) prüft zusätzlich: Wald reicht als Zunge in die Wiese, Waldboden tief im Wald, offene Wiese in der Mitte, kein Baum in zwei Zonen, Mündung frei, kein Baum auf einem Weg, Gürtel um die Wiese, Kronenmeer jenseits des Nordrands und nicht über spielbarem Boden, Schleier zu bei frischem Wald und offen nach dem Laden, Naht außerhalb der Schwelle ist Wand.
- **Sichtprüfung:** `zone_lab.tscn -- --at=x,y --capture=/abs.png`, Stellen: Naht 1140,966, Nordrand 1062,918, Lichtung 1220,955, Westrand 1018,990.
- **Noch nicht:** andere Grenzarten als `forest_sea` (Klippe, Wasser, Leere), Fernsicht über Kontinentgrenzen, Kollisionsring 2 Tiles außerhalb (die Wand liegt am Umriss, der Gürtel steht davor), große Zonen mit Oberflächen in Kacheln.

### 13.5 Was Schritt 5 gebaut hat (Stimmung & Ankommen)

- **`ZoneMood`** (src/world/v2/zone_mood.gd, ein Kind des `ZoneDirector`, lokal auf jedem Rechner, rein kosmetisch). Die Profile stehen in `data/world/moods.json`, eine Zone nennt ihres mit `mood`.
  - Felder: `tint_day`/`tint_night` (Weltlicht), `sun` (direkte Sonne und goldene Stunde), `shadow`/`light` (Tönung des Farbgrads), `vibrance`/`contrast`/`bloom`/`vignette` (zum Farbgrad addiert), `wind` (Böen aller Pflanzen), `motes` (Pollen), `amb_day`/`amb_night`/`amb_wind`/`amb_crickets` (Klangbetten). Jedes Feld ist neutral, wenn es fehlt.
  - Überblendung: An der Kamera mischt `ZoneMood` die Profile der Zonen in der Nähe nach dem vorzeichenbehafteten Abstand zum Umriss. 15 Tiles innen gilt die eigene Stimmung, auf der Naht je zur Hälfte, insgesamt etwa 30 Tiles. Über die Zeit nähert sich das Bild mit 1,4/s an, ein Sprung über 40 Tiles setzt es sofort.
  - Ein Ort lehnt die Stimmung an (`mood` + `mood_amount` im Ortseintrag, voll nach 6 Tiles im Ort): Der Moosgrund im Labor ist eine helle, pollenreiche Lichtung (`forest_glade`) im dunklen Wald.
  - Veröffentlicht als `ZoneMood.now` (statisch, `{}` ohne Zonenwelt). Gelesen von `DayNight` (Licht, Sonne), `MoodGrade` (Farbgrad), `WorldWind` (Böen), `DayMotes` (Pollen) und `DayAmbience` (Betten). Ohne Zonenwelt sind alle Werte neutral, die alte Welt bleibt unverändert. Kosten: ~90 µs pro Frame.
- **`ZoneArrival`** (src/ui/zone_arrival.gd, CanvasLayer 21, nur der lokale Spieler):
  - Erstes Betreten einer Zone: Der Name erscheint getippt in Gold in doppelter Größe, darunter der Beiname. Ranken wachsen zu beiden Seiten. Daneben liegt eine kleine Karte, auf der sich der Umriss der Zone in zwei Sekunden zeichnet, mit einem goldenen Punkt an der Eintrittsstelle. Dazu kommt ein leiser Tuchklang (`town/banner_unroll`).
  - Wiederkehr: nur der Name klein mit kurzen Ranken, 2 Sekunden.
  - Orte: Der Name steht klein unter der Uhr, beim ersten Mal mit dem Stempel ENTDECKT (`skills/reveal`).
  - Alles wartet bei Pause, Dialog, `InputManager.ui_blocking`, `story_lock` oder einem Schattenwesen mit Leben innerhalb von 220 px, und es hält an, solange etwas den Bildschirm verdeckt.
  - Gesehenes steht in `ZoneDirector.seen` und wird im Zonenblock gespeichert (`seen.zones`, `seen.places`).
- **Labor:** `zone_lab.tscn -- --at=x,y --capture=/abs.png --hold=Sekunden` macht die Aufnahme nach dieser Zeit (die Einblendungen laufen in Echtzeit). Die Laborzeilen stehen unter der Ortszeile.
- **Tests:** `tools/test_zone_lab.tscn` (`ZONE LAB OK`, 58 Prüfungen) prüft zusätzlich:
  - die eigene Stimmung tief im Wald, sonnig und windig auf der Wiese, halb und halb auf der Naht;
  - die Anlehnung des Moosgrunds und den sanften Übergang (kein Sprung über 0,1 Sonne pro 6 Tiles);
  - dass `ZoneMood.now` veröffentlicht wird und günstig ist;
  - das große Schild beim ersten Betreten und die schmale Zeile bei der Rückkehr;
  - die Ortsentdeckung und dass Gesehenes gespeichert wird.
- **Noch nicht:** Musikfamilie pro Zone (`MusicDirector` kennt nur Tag/Nacht/Kampf/Gloom/Arid), Wetterprofil pro Zone (`WeatherManager`), Nebelgrundwert der Nacht, Leerenschrift (`VoidTitle`) für Leerenzonen.

### 13.6 Was Schritte 6–10, ALTMARK & WINDKAP gebaut haben (2026-11-24)

- **Kontinent ALTMARK & Kartenmaler (`tools/build_altmark_world.py`, `tools/paint_zone_map.py`, `tools/check_atlas.py`, `tools/check_zone.py`):**
  - Kompakter fraktaler Inselkontinent (`2400 × 1800` Tiles, Landmasse `~1520 × 1336` + 25 biom-passende Schäreninseln im offenen Meer, 5 Landstriche, 11 Zonen über gemeinsame `seams`, Leerenriss-Wunde nur am Ostrand von `varnholm`).
  - `paint_zone_map.py` backt alle 11 Zonen- (`map.png`, `map_light.png`, `far.png` bei `4 px/Tile`) sowie Kontinentkarten (`continent_map.png`, `continent_light.png`, `continent_engraving.png`, `continent_water.png`) im geditherten Stufenplateau-Stil von `firebase/public/map.mjs` (`0` `#000000`-Pixel) mit eingeschnittenen Flusstälern, trichterförmigen Flussmündungen und randlosen Seen im Meer-Stil.
- **Spielbare Startzone WINDKAP (`src/world/v2/zone_world.gd`, `src/world/v2/windkap_props.gd`, `assets/shaders/ocean_horizon.gdshader`):**
  - Class-L-Küstenzone (`291 × 229` Tiles bei `[434, 1175]`, `RUHIG`) mit 6 benannten Orten, Küstenlager (brennendes Lagerfeuer, sitzbare Treibholzbänke, Vorratskiste, Schwert- & Axt-Ständer), Steinsetzer-Leuchtturmruine + interaktiver Kartentafel (`unlock_continent_solemn`) + `VistaPoint`, Steinbogenbrücke über den *Erlenbach*, erweckbarer *Wächterin der Bucht* (`bucht_waechterin`), 2 Rätseln/Truhen, 3 physischen Schwellen-Blockern mit `E`-Hinweisen + nahtlosem `ZoneBackdrop` gegen Platzhalter-Nachbarn, freiem Küsten-/Bach-Schwimmen (>14 Tiles sanfte Abdrift & Ausdauerzug + Meereshorizont), v2-Flora/Fauna inkl. Krähen-Haustieren und `RUHIG`-Nächten + Lichtfischern.
- **Lebendiger 4-Ebenen-Atlas & Match-Cut (`src/ui/atlas_view.gd`, `src/ui/map_window.gd`, `assets/shaders/atlas_{zone,continent,world}.gdshader`):**
  - Stufenloser Zoom `ORT -> ZONE -> KONTINENT -> WELT`, `16 px/Tile`-Match-Cut aus der Live-Kamera in die Tuschekarte, `2×2`-Tile-Nebel pro Zone (`MapDiscovery`), Steinsetzer-Gravur mit scharfen `1:1`-`PixelText`-Namen, lebendiges Licht/Nacht/Wetter/Wolken/Lagerfeuer und Caelias verdichtendes Schleiergewebe (`veil_progress`).
- **Koop-Zonenstreaming (`src/world/v2/zone_director.gd`, `src/world/v2/zone_coop.gd`, `src/fx/map_ping_pillar.gd`, `tools/test_zone_director.tscn`):**
  - Host streamt um alle Peers (inkl. gehaltener Außenzone bei `PocketSpace`), jeder Client streamt strikt nur um den eigenen lokalen Spieler; `MultiplayerSynchronizer`-Sichtbarkeitsfilter und peer-gefilterte `LivingTree`-RPCs verhindern Desyncs/Pfadfehler (`0` RPC-Fehler über 2 Prozesse in `test_zone_director.tscn`, 75 Checks). Mittelklick-Kartenruf (`MapPingPillar`) und „ZU IHM“-Reise (`request_join_peer` / goldene `Atlas.route()`-Linie).
- **Reisen, Schleierfäden & AtlasBook (`src/ui/atlas_book.gd`, `src/systems/veil_threads.gd`, `src/entities/props/veil_thread_pickup.gd`, `src/ui/death_screen.gd`):**
  - 8 geteilte Schleierfäden in `WINDKAP`, zonenübergreifende Wegstein-Schnellreise mit Schleier-Kamerazug, Todeskarten-Respawnwahl (`WEGSTEIN` vs. `KÜSTENLAGER`) sowie integriertes `AtlasBook` (`B`/`C` oder Klick auf Erschließungs-Blüte) mit einlösbaren `30% / 60% / 100%`-Belohnungen (*Küsten-Kartenstempel `WINDKAP-WELLE`*, *Silberküsten-Rahmenranke*, *Spielertitel „KIND DER BUCHT“*).

---

## 14. Entscheidungen (alle getroffen am 2026-11-23)

| # | Frage | Entscheidung | Wo im Konzept |
|---|---|---|---|
| 1 | Slots oder echte Kontinentkoordinaten? | **Echte Kontinentkoordinaten.** Jede Zone liegt an ihrem `origin`, die Slots der Testwelt entfallen, die Taschen ziehen in den negativen Quadranten. | 4.1, 4.2 |
| 2 | Übergänge nahtlos oder mit Schnitt? | **Nahtlos** für Pfad, Pass, Furt, Brücke und Sprung. Tunnel, Fähre, Schiff und Wegstein bleiben harte Übergänge. | 5.2 |
| 3 | Schwierigkeit? | **Mischung:** Die Grundstärke ist überall gleich und steigt mit der Nacht, dazu ein Gefahrengrad pro Zone (RUHIG / RAU / WILD = +0 / +20 / +40 % auf Nachtbudget, Elite-Chance und Rudelgröße). Keine Levelsperren, nur die Nacht ist betroffen. | 6.6 |
| 4 | Wo darf gebaut werden? | **Stadt nur in der Heimatzone.** Außenposten in anderen Zonen später als eigener Schritt. | 3.1 |
| 5 | Respawn am Wegstein? | **Ja, wählbar** auf der Todeskarte (ZUHAUSE oder der erweckte Wegstein der aktuellen Zone). | 6.6 |
| 6 | Schleierfäden und Atlasbuch? | **Ja, beides.** | 8.2 |
| 7 | Kanalnetz als zweites Reisenetz? | **Nein.** Schnellreise nur über Wegsteine. | 10 |
| 8 | Unbekanntes auf dem Kontinent? | **Steinsetzer-Gravur.** In der Zonenkarte bleibt der Schattenrauch. | 9.5 |
| 9 | Schleier auf der Weltkarte? | **Ja**, als Fortschritt der Geschichte. | 9.5 |
| 10 | Ab wann ist die Zonenwelt die Hauptwelt? | **Ausgeführt (2026-11-23, M1):** `src/world/v2/zone_world.tscn` ist die alleinige Hauptwelt für `GameLauncher`, `MainMenu` (`MenuWorld`) und `PauseMenu` ohne `WorldLevel`-Fallback (`world_level.gd` verbleibt nur für bestehende Subsystem-Tests). `SaveGame.VERSION = 2` (v1-Saves starten frisch am Küstenlager in `WINDKAP`), `Interiors`/`MineManager`/`StarHallRoom` liegen über `PocketSpace` im negativen Quadranten (`x, y < -16000`), die v1-Zonentestwelt (`src/world/zones/`, `data/continents.json`, `data/zones/`, `zone_map_view.gd`, `test_zones.*`, `preview_zones.*`) ist gelöscht, und `labor_wiese` ↔ `labor_wald` ist in `"lab"` isoliert. | 13 |
| 11 | Kontinentebene sofort oder per Fund? | **Per Story-Fund (finalisiert):** Am Anfang sind nur `ORT` und `ZONE` freigeschaltet (Rankenstopp am Rand). **Windkaps Steinsetzer-Kartentafel** (*Steinsetzer-Tafel* am *Windkap*) schaltet Kontinent- und Weltkarte sowie ALTMARKs Gravur feierlich frei (+ Dev-Schalter). | 9.5 |
| 12 | Kontinent ALTMARK & Weites Meer | **`continents/main.json` (2400 × 1800 Tiles):** Gemäßigter Inselkontinent mit 5 Landstrichen (*Südwestküste*, *Grünland & Zinnen*, *Der Glaskamm*, *Der Hexenwald*, *Das Leerenblühen*) und ~11 handgeplanten Zonenpolygonen über gemeinsame `seams`. Ringsum bis zum Kartenrand reines weites Meer mit Strömungen (keine weiteren Kontinente, kein künstlicher Leerenring um das Meer); eine Leerenriss-Wunde gibt es nur am Großen Riss im östlichen Varnholm / *Leerenblühen*. | 2, 9.5 |
| 13 | Startzone WINDKAP | **Class L (~280 × 250 Tiles, SW-Küste, `RUHIG`):** 6 benannte Orte (*Die Silberbucht* mit Küstenlager, sitzbarem Lagerfeuer, Kiste, Starter-Schwert & -Axt; *Das Windkap* mit Steinsetzer-Ruine/Leuchtturm-Silhouette, Kartentafel und `VistaPoint`; *Der Erlenbach* mit Bogenbrücke; *Die Apfeltrift*; *Der Wächterhain* mit erweckbarem Wegstein *Wächterin der Bucht*; *Der Kronensaum* mit 1–2 Rätseln/Truhen und 3 physisch blockierten Binnenland-Schwellen samt `E`-Hinweisen & `ZoneBackdrop`). Freies Küsten-/Bach-Schwimmen (`REGIME_SURF`, `REGIME_OCEAN`, `REGIME_BROOK`) mit sanfter Abdrift & steigendem Ausdauerverlust jenseits ~14 Tiles + endloser Meereshorizont, 8 handgesetzte Schleierfäden, v2-Flora/Tierwelt (inkl. Krähen-Haustiere), echte Nächte (`RUHIG` + Lichtfischer). | 3, 5 |
| 14 | Kartenbake 4 px/Tile & Gravur | **`tools/paint_zone_map.py` (4 px/Tile):** Backt `map.png`, `map_light.png` und `far.png` mit `4 px/Tile` für scharfen `ORT`-Zoom (`2–6 px/Tile`) und einen nahtlosen `16 px/Tile`-Match-Cut beim Öffnen von `M`, plus ALTMARKs monochrome Steinsetzer-Gravur mit alten Ortsnamen für unkartierte Gebiete. | 9.5, 11, 12.1 |

**Noch offen, aber nicht blockierend:** Feintuning der Gefahrengrade und das Konzept für Außenposten in fremden Zonen (eigener späterer Schritt).
