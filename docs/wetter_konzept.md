# Konzept: Wettersystem (Sonne, Wolken, Regen, Sturm)

Status: Konzept, noch nichts gebaut. Umsetzung in vier Schritten (Abschnitt 11).
Stand der Bestandsaufnahme: 2026-11-10.

## 1. Ziel und Spielgefühl

Das Wetter soll die Welt spürbar verändern, ohne zu stören. Man soll es **sehen** (echte Wolken, Wolkenschatten, Regen im Wind), **hören** (Wind, Regen, Donner) und **an der Welt ablesen** (nasser Boden, Pfützen, Tiere, Pflanzen, Wasser).

- Sonnig: klar, warm, bewegte Lichtflecken, Sonnenstrahlen durch die Kronen.
- Bewölkt: wenig Wolken (einzelne Puffs mit wandernden Schatten), viele Wolken (Lichtflecken huschen über das Land), bedeckt (diffuses graues Licht, kaum Schatten).
- Regen: Nieselregen, Regen, Starkregen. Das Land wird dunkler, kühler, nass; Tropfen fliegen mit dem Wind.
- Sturm: Starkwind, schräger Regen in Böen, Gewitter mit Blitz und Donner. Bäume biegen sich, Laub und Zweige fliegen.

Das Wetter ist Stimmung und Spielwelt, keine Strafe. Es nimmt dem Spieler nichts weg und blockiert keine Story. Mögliche spielerische Folgen (Abschnitt 9) sind Vorschläge zur Entscheidung.

## 2. Ausgangslage im Projekt (was wir nutzen)

| Vorhanden | Ort | Rolle fürs Wetter |
|---|---|---|
| Wind: Richtung, Böe, Schader-Globals `g_wind_dir/gust/clock` | `WorldWind`, `data/wind.json` | bekommt eine **Stärke** vom Wetter; Regen und Laub fliegen darin |
| Wolkenschatten (eine Sinus-Funktion, 0.62..1.0) | `day_cloud()` in `daylight.gdshaderinc`, Spiegel auf der CPU in `DayMotes` | wird durch ein echtes Wolkenfeld ersetzt |
| Tageslicht, Kronenmaske 128x96 | `DaylightField`, Global `g_day_cover` | **Unterstand**: unter Kronen regnet es weniger |
| Sonne / Goldstunde / Tau | `TimeManager.sun_amount/golden_amount/dew_amount`, gespeist in `DayNight._update` | eine einzige Naht: `DayNight` multipliziert mit dem Wetter |
| Nässe: feuchte Tage (32 %), Nebelnächte | `Moisture.wetness()/is_wet_day()` | wird vom Wetter getragen (Regen macht nass, trocknet) |
| Farbstimmung | `MoodGrade`, `data/mood.json` | Regen/Sturm entsättigen und dunkeln |
| Nacht: Nebel, Mond | `NightAtmosphere`, `NightRules.special_for` | Wolken decken den Mond ab; Nebel wird ein Wetterzustand |
| Wasser: Störungen/Schwimmer | `river_water.gdshader` (`disturbances`, `swimmers`) | Regenringe auf Flüssen und Seen |
| Luftpartikel (Samen, Blätter), Budget 8 | `WorldWind._air` | im Sturm mehr und anderes Treibgut |
| Klang: Tages-/Nachtbett | `DayAmbience`, `tools/audio_daynight.py` | Wind-, Regen-, Donnerbetten |
| Alchemie-Bedingung bekommt das Wetter übergeben | `AlchemyRules.condition_block` | später Regenwasser-Zutaten |
| Entwicklermenü | Pausenmenü ENTWICKLER | Wetter setzen, Vorschau |

Wichtig: Der Wind läuft heute auf einer **lokalen Uhr pro Peer** (rein kosmetisch). Wetter muss dagegen auf allen Peers dasselbe sein.

## 3. Leitentscheidungen (mit Begründung)

1. **Das Wetter ist eine reine Funktion von Weltseed + Weltzeit** (wie `Moisture` und `NightRules.special_for`). Kein Netzwerkverkehr für das Wetter selbst, nichts im Speicherstand, jeder Peer rechnet dasselbe. `TimeManager` synchronisiert die Zeit schon alle 2 s. Nur der Entwickler-Override (Wetter erzwingen) wird vom Host gesendet.
2. **Wetterlagen sind eine Kette aus Segmenten** (Markov-Kette mit Dauer, vom Start deterministisch erzeugt, inkrementell gecacht). Das gibt Kontrolle (Übergangstabelle, Mindestdauer, Tageszeit-Gewichte, Story-Sperren) und fühlt sich glaubwürdig an (nach Regen kommt Aufklaren, nicht Sonne im Sekundentakt).
3. **Wolken sind ein echtes räumliches Feld in Weltkoordinaten**, das mit dem Wind driftet. Wolkenschatten, sichtbare Wolken und Regen lesen **dasselbe Feld**. Dadurch gibt es Regenzellen: Man sieht eine dunkle Wolke mit Regenvorhang näher kommen, es regnet erst, wenn sie über einem ist, und sie zieht weiter.
4. **Das Feld kommt aus Texturen, nicht aus doppelt geschriebener Mathematik.** Eine einmal beim Start erzeugte, kachelbare Rauschtextur (aus dem Weltseed) wird von GPU-Shadern und von der CPU gelesen. So können GPU und CPU nie auseinanderlaufen (das Tageslicht hat dafür heute einen eigenen Paritätstest).
5. **Regime global, Ausprägung lokal.** Die Wetterlage (Bewölkungsgrad, Regenrate, Windstärke) gilt weltweit; das Wolkenfeld verteilt sie räumlich. Bodennässe ist global (aus dem Verlauf der Lagen), nur der sichtbare Regen ist lokal.
6. **Pixelstil bleibt.** Alles auf dem 640x360-Raster, ganze Pixel, wenige Töne, Bayer-Dither an Rändern (wie `ground_tone`, `night_fog`). Keine weichen Verläufe über Wolken, keine Antialiasing-Streifen.
7. **Eine Naht für Licht.** `TimeManager` bleibt die Astronomie (Sonnenhöhe). `DayNight._update` multipliziert Sonne, Goldstunde und Tau mit dem Wetter und gibt neue Globals aus. Verbraucher (Fische, Pollen, Nachtdirektor) fragen den Wetter-Knoten, nicht jeder rechnet selbst.
8. **Innenräume und Mine haben kein Wetter**, nur Geräusch (Regen auf dem Dach, Tropfen). Wie beim Tageslicht: `indoors` schaltet alles aus.

## 4. Wetterzustand und Wetterlagen

### 4.1 Zustandsvektor

`WeatherState` (alle Werte 0..1, ausser Richtung):

| Feld | Bedeutung |
|---|---|
| `cloud` | Bewölkungsgrad: 0 klar .. 1 dicht |
| `rain` | Regenrate (Nieseln .. Starkregen) |
| `wind` | Windstärke (0 still .. 1 Sturm) |
| `storm` | Gewitterstärke (Blitz, Donner, Böenwände) |
| `fog` | Dunst/Nebel (Morgen, nach Regen) |
| `dir` | mittlere Windrichtung (Bogenmass) |

Abgeleitet: `sunlight()` (wieviel Sonne ankommt), `darkness()`, `ground_wet()`, `name()` (für die Anzeige).

### 4.2 Wetterlagen

| Id | Name | cloud | rain | wind | storm | typisch |
|---|---|---|---|---|---|---|
| `clear` | KLAR | 0.04 | 0 | 0.15 | 0 | Sonne, wenige Schleier |
| `fair` | HEITER | 0.25 | 0 | 0.25 | 0 | wenige Puffs, ziehende Schatten |
| `broken` | WOLKIG | 0.55 | 0 | 0.35 | 0 | Sonne wechselt mit Schatten |
| `overcast` | BEDECKT | 0.85 | 0 | 0.35 | 0 | graues, diffuses Licht |
| `drizzle` | NIESELREGEN | 0.80 | 0.20 | 0.25 | 0 | feine kurze Striche, leise |
| `rain` | REGEN | 0.90 | 0.50 | 0.50 | 0 | gleichmässig, schräg im Wind |
| `downpour` | STARKREGEN | 1.00 | 0.85 | 0.70 | 0 | dicht, Pfützen, Rauschen |
| `storm` | GEWITTER | 1.00 | 0.90 | 1.00 | 1 | Starkwind, Blitz, Donner |
| `gale` | STURMWIND | 0.55 | 0 | 0.90 | 0.3 | trockener Sturm, Treibgut, Staub |
| `fog` | NEBEL | 0.60 | 0 | 0.05 | 0 | Dunst, vor allem Morgen |

Zahlen sind Startwerte, alles in `data/weather.json`.

### 4.3 Segmentkette

- Segment = Lage + Dauer (Anteile eines Tages, 12 Minuten). Richtwerte: klar/heiter 0.35..0.9 Tag (4..11 min), wolkig 0.25..0.6, Regen 0.15..0.4, Starkregen 0.1..0.25, Gewitter 0.08..0.18 (1..2 min Kern), Sturmwind 0.1..0.3, Nebel 0.1..0.25.
- Übergänge: gewichtete Tabelle je Lage (z. B. `heiter` -> klar 25 %, wolkig 45 %, heiter 20 %, Nieselregen 10 %). Regen steigert sich über Nieseln -> Regen -> Starkregen -> Gewitter und klingt in umgekehrter Richtung ab (Gewitter geht nie direkt in Klar). Gewichte hängen von der Tageszeit ab (Nebel eher morgens, Gewitter eher spätnachmittags/abends, nachts weniger Klar-Wechsel).
- Zielverteilung über viele Tage: etwa 45 % trocken-sonnig (klar/heiter), 20 % wolkig, 10 % bedeckt, 20 % Regenfamilie, 4 % Gewitter, 1 % Sturmwind/Nebel. In `weather.json` einstellbar.
- Übergang zwischen Segmenten: Parameter werden über ca. 0.04 Tag (30 s) weich geblendet, nie hart umgeschaltet. Wolkenfeld und Wind sind ohnehin stetig.
- **Weltzeit (`epoch`)** = `TimeManager.day` plus Anteil seit Sonnenaufgang (`fposmod(time_of_day - DAY_START, 1)`): stetig über Mitternacht (die Stunden vor Sonnenaufgang gehören noch zum alten Tag, wie in `Moisture`).
- **Zeitsprünge** (F4, Cheat, Schlaf-Szenen) springen die reine Funktion; die sichtbare Anzeige glättet (`WeatherManager` nähert die lokalen Werte in 3..8 s dem Ziel).
- **Story-Sperren** (`data/weather.json` `forced`): der Anfang (Tag 1/2, solange `WorldLevel.opening_over` falsch ist, Uhr gesperrt) ist heiter. Einzelne Story-Szenen können eine Lage erzwingen und wieder freigeben (`WeatherManager.force(id, seconds)`), z. B. dichte Wolken beim Hinterhalt, Regen bei einer Trauerszene. Standard: keine Eingriffe.

## 5. Wolken und Wolkenschatten

### 5.1 Das Wolkenfeld

`cloud_density(pos, t)` in 0..1:

- Rauschtextur A (grosse Massen, Kachelgrösse ca. 1800 px) plus Textur B (Details, ca. 420 px), beide aus dem Weltseed, beide kachelbar.
- Position wird um den **Drift** verschoben: `p - drift(epoch)`; der Drift ist die Summe der Segmentbeiträge (`Richtung * Tempo * Dauer`), also eine reine Funktion der Zeit und stetig. Die Wolken ziehen genau so, wie der Wind weht.
- Dichte wird gegen die Lage geschwellt: `coverage = smoothstep(1 - cloud - soft, 1 - cloud + soft, noise)`. Bei `cloud` 0.25 gibt es einzelne Inseln, bei 0.55 zusammenhängende Massen mit Lücken, bei 0.85+ eine geschlossene Decke mit hellen Löchern, bei 1.0 gar keine Lücken.
- Die CPU liest dieselben Texturen (bilineares Sampling mit derselben Mathematik, Parität wird getestet).

### 5.2 Wolkenschatten

- `day_cloud(p)` in `daylight.gdshaderinc` wird zu `day_cloud(p)` = Licht aus dem Wolkenfeld. Alle Verbraucher (Boden, Props, Flora, Akteure, Wasser, Gebäude) bekommen die Schatten ohne eigene Änderung, weil sie schon `day_local()` benutzen.
- Bei **wenig Wolken**: scharfe, kleine, dunklere Schatten, dazwischen helles Gold. Bei **vielen**: grosse, weichere Schatten, Licht wandert in Flecken. Bei **bedeckt**: keine einzelnen Schatten mehr, nur gleichmässig gedimmtes, kühles Licht (realistisch, und sieht ruhig aus).
- Schattenränder werden gedithert in ganzen Pixeln, nicht weich.
- Der Schatten ist die einzige Information, die sehr dunkel sein darf; Figuren, Kampfzonen und Dialoge bleiben lesbar (Untergrenze 0.55 Licht).
- `DayMotes` (Pollen) erscheinen nur im Sonnenfleck: sie lesen das Feld über dieselbe Textur.

### 5.3 Sichtbare Wolken

Ein Vollbild-Quad unter dem HUD (wie `NightAtmosphere`, neuer Shader `weather_clouds.gdshader`), weltverankert:

- **Zwei Schichten**: hohe dünne Schleier (schnell, sehr hell, nur bei klarem/heiterem Wetter und in der Goldstunde) und die Hauptschicht.
- **Höhenversatz**: Eine Wolke wird nicht über ihrem Schatten, sondern leicht nach oben-links versetzt gezeichnet (Licht kommt von oben links, der Schatten fällt nach unten rechts). Der Versatz wächst mit tiefer stehender Sonne. Das gibt echte Höhe in der 3/4-Ansicht und zeigt zugleich, welche Wolke welchen Schatten wirft.
- **Look**: 4 Töne (helle Oberseite, Mitte, graue/violette Unterseite, dunkler Kern), Bayer-Dither an den Rändern, ein Pixel Rand. Heiter = einzelne Puffs mit leichtem Wabenmuster, wolkig = Massen mit Lücken, bedeckt = geschlossene graue Decke mit hellen Löchern, Gewitter = dunkle, tief hängende Decke mit gewölbten Rändern und im Kern violetter Unterseite.
- **Tageszeit**: Goldstunde färbt Oberkanten warm, Dämmerung violett-rosa, Nacht dunkle Massen, die den Mond verdecken (Mondlicht und -flecken in `night_moon` werden mit dem Wolkenfeld multipliziert; Wolkenlücken lassen Mondpfützen durch).
- **Durchsicht**: Wolken sind halbtransparent (Alpha je nach Dichte, max. ca. 0.55), damit das Spiel lesbar bleibt. Unter Innenräumen, in der Mine und in Story-Sperren nicht gezeichnet.
- **Rand-Ankündigung**: Eine herannahende Regenzelle zeigt sich als dunklere Wolke mit einem **Regenvorhang** (diagonale, grau-blaue Schleier unter ihr), die auf dem Bildschirm einschwebt, ehe es bei einem selbst regnet.

## 6. Regen

### 6.1 Fallender Regen (Bildschirm)

Ein Vollbild-Shader (`weather_rain.gdshader`), **keine Partikelobjekte**, damit Starkregen nichts kostet und es kein Budget gibt:

- 3 Tiefenschichten (fern: dünn, kurz, blass, langsam; mittel; nah: lang, hell, schnell). Jede Schicht ist ein Zellraster, aus dem Tropfen gehasht werden; die Schichten sind leicht mit der Kamera mitgeführt (Parallaxe), damit Tiefe entsteht.
- Tropfen sind **1 px breite Striche in ganzen Pixeln**, Länge und Neigung aus der Fallgeschwindigkeit. Dichte und Helligkeit aus `rain` und der **lokalen Regenstärke** am Kameraziel.
- **Wind trägt den Regen**: Neigung = Windvektor (x) mal Faktor, gespeist aus `WorldWind` über Shader-Globals (`g_wind_dir`, `g_wind_gust` existieren bereits). Böen kippen die Tropfen kurz weiter, in Starkwind fast waagerecht; die Fallgeschwindigkeit hängt leicht von der Windkomponente zur Kamera ab. Regen und Gräser/Kronen neigen sich also im selben Takt.
- **Regenvorhänge**: In Böen laufen helle diagonale Schleier über das Bild (Wellenfront in Windrichtung), Starkregen und Sturm besonders.
- **Unterstand**: Die Dichte wird mit der Kronenmaske (`g_day_cover`) gedünnt. Unter Bäumen fallen wenige Tropfen, dafür fallen dort grössere, seltene Tropfen von den Kronenrändern (kleine weiter fallende Striche). Im Innenraum kein Regen.
- **Dunkel/Entsättigung**: `MoodGrade` zieht Farbe und Kontrast zurück, Vignette etwas stärker, ferne Dinge verschwinden in Dunst.

### 6.2 Auftreffen (Welt)

- **Spritzer auf dem Boden**: kleine weltverankerte Pixelringe/Spritzer an zufälligen sichtbaren Orten, Anzahl nach Regenstärke (Obergrenze z. B. 60 sichtbar), sie sterben in 0.25 s. Sie sitzen auf dem Boden (z unter den Akteuren), nicht unter Kronen/Dächern.
- **Wasser**: Regenringe auf Flüssen und Seen (neuer Parameter im Wasser-Shader, pro Pixel gehashte, gedithert expandierende Ringe); stärkerer Regen macht die Oberfläche unruhiger und trübt Glanz.
- **Nasser Boden**: `ground_tone` bekommt `wet` (dunklerer, kühlerer Ton, glänzende Stellen), Pfützen als weltverankerte dunkle Flecken mit Spiegelung des Himmels und Ringen, entstehen bei Starkregen, trocknen mit der Zeit. Pfützen sind nur Dekor (keine Kollision), Laufen darin spritzt (bestehender Wasser-Fussabdruck-Pfad).
- **Nasse Spuren**: Fussabdrücke im Regen füllen sich kurz, Ellie wird nass (`Player._wet` gibt es schon, `soak`-Shader): im Regen langsames Nasswerden, unter einem Dach/Baumkrone trocknet sie.
- **Blätter und Gras**: Pflanzen biegen sich schwerer, Tropfen auf Blättern (Glanzpixel), Pilze/Moos öffnen sich nach Regen (hängt an `Moisture`).
- **Nach dem Regen**: der Boden trocknet gemäss `DRY_OUT`; bei Sonne danach dünner **Dampf** über dem Boden und besonders helle, kräftige Sonnenstrahlen durch die Wolkenlücken (verstärkte `shaft_*`), Tau-Look bleibt (bestehendes `g_dew`).

### 6.3 Ton

Regen-Bett als Schleife je Stärke (Nieseln, Regen, Starkregen), überblendet nach lokaler Regenstärke; Material unter den Füssen verändert nur Tropfen am Boden (Gras, Stein, Holz, Wasser). Innen: gedämpfter Regen auf dem Dach plus Tropfen. Unter Kronen: dumpfer, einzelne dicke Tropfen. Synthetisierte Platzhalter in `tools/audio_weather.py` (wie die übrigen Audioskripte).

## 7. Sturm

### 7.1 Wind

- `WorldWind` bekommt `strength` (0..1) aus dem Wetter und skaliert `sample()`, Böenhäufigkeit und -höhe: still 0.6x, normal 1x, Sturm bis ca. 3x. Richtung dreht sich bei Frontdurchgängen (kurzer Wirbel statt gerader Richtungsänderung), im Sturm turbulenter (Richtungsjitter).
- Alle Vegetations-Shader (`flora_wind`, `meadow_details`, Büsche, Kronen) skalieren mit; die Obergrenze der Verformung bleibt Pixelraster-konform (Wurzeln fest, ganze Pixel). Die Biom-Exponiertheit (`exposure` in `wind.json`) gilt weiter: Glasklippen sind windiger, Wälder geschützter.
- **Treibgut**: das Luftpartikel-Budget (heute 8) wird im Sturm angehoben (z. B. 40) und bekommt neue Arten: Blätter, kleine Zweige, Staub/Pollenwolken, im Hexenwald Asche. Sie fliegen waagerecht im Windfeld, drehen sich, verschwinden hinter dem Rand der Kamera. Weiterhin keine Physik, nur Zeichnung.
- **Böenwand**: bei Gewitterbeginn kurze Böe mit sichtbarer Staub- und Laubfront, die über den Bildschirm läuft.
- **Bäume im Sturm**: Kronen schwingen stark, einzelne Äste sehen aus, als brächen sie nicht ab (kein Schaden). Fällbare Bäume und Ernte bleiben unverändert.
- **Wasser**: Wellen laufen mit dem Wind, Schaumkronen im Sturm, Angeln wird schwerer (siehe 9).

### 7.2 Gewitter

- **Blitz**: seltene Ereignisse (Abstand 6..25 s je Stärke), host-unabhängig aus der Weltzeit bestimmt (reine Funktion: Zeitscheiben mit gehashten Blitzzeiten und -orten), damit alle Peers gleichzeitig blitzen. Ein Blitz ist: Vollbild-Aufhellung (2 Pixelstufen, weisslich-violett, 0.12 s plus Nachflackern), ein gezackter 1-px-Blitzpfad aus dem Himmel zu einem Ort im Bild (nicht auf Spieler gezielt), harte Schatten für einen Moment.
- **Donner**: Verzögerung nach Entfernung (z. B. 340 px/s gedehnt, 0.3..3 s), Lautstärke nach Entfernung, drei Klangvarianten (Knall nah, Rollen fern). Nicht gleichzeitig mit Kampftreffern (kein Maskieren wichtiger Hinweise: Warnklänge bleiben vorn).
- **Himmel**: tiefe dunkle Decke, `darkness()` bis ca. 0.45 Tageslicht; Laternen und Feuer der Stadt wirken wärmer (Kontrast).
- **Leere-Note**: nahe am Weltrand (`VoidEdge`) wird der Blitz magenta-violett und der Regen fällt sichtbar in die Leere hinein. Der Hexenwald hat sein eigenes grünliches Licht (`#a8ff6a`): dort färbt der Blitz grün-weiss.
- **Kein Blitzschaden** im ersten Wurf (rein visuell). Blitzeinschläge in Bäume als Verkohlen/Funken sind eine spätere Option.

## 8. Regionales Klima

Die Welt hat fünf Gebiete plus den Hexenwald (`supers[].name`, `own_biomes`). Das Wetter selbst ist weltweit gleich, aber jede Region **moduliert** es leicht (Datei `weather.json` `regions`):

| Gebiet | Modulation |
|---|---|
| Die Lichtung | Standard |
| Nebelwald | mehr Nebel/Nieseln, Wind geschützt (exposure) |
| Glasklippen | mehr Wind, Regen prasselt, Funken auf Kristall, Blitzanziehung (Optik) |
| Versunkene Ruinen | mehr Regen/Nebel, Pfützen bleiben länger |
| Das Leerenblühen | violetter Einschlag, Regen wirkt wie Asche, Blitze magenta |
| Hexenwald | permanent trübe: Klar wird zu Dunst, Regen leiser, Nässe hält länger, grüner Blitz (er hat schon permanente Dämmerung, `BiomeBlend`) |

Umsetzung: `BiomeBlend.amount_at(pos)` und die Super-Region am Ort liefern Gewichte; `WeatherManager.at(pos)` mischt die globale Lage mit den Regionswerten. Heute ist die ganze Welt ein Wiesenbiom, die Regionen sind also zunächst nur Namen; die Modulation wird als Daten angelegt und ist anfangs nahezu leer.

## 9. Auswirkungen auf Welt und Spielwelt (Vorschläge)

Rein kosmetisch (immer):

- Tiere: Rehe/Hasen/Vögel suchen bei Regen Unterstand oder bleiben ruhiger, Krähen sitzen unter Kronen, Frösche werden aktiver, Schnecken zeigen sich (hängt schon an `Moisture`); im Sturm fliegen kaum Vögel. Schmetterlinge, Bienen, Marienkäfer pausieren bei Regen und Wolken; Motten wie bisher nachts.
- Pflanzen: Blumen schliessen bei Regen/Bedeckung (`Flora` `sun`-Logik liest `sunlight()` statt Uhr), Pilze und Moos kommen schneller (`Moisture`), `PlantSowing` Samen fassen besser.
- Stadt: Siedler suchen im Regen Unterstand und gehen später wieder raus, Valdric/Gustav arbeiten drinnen oder unter dem Vordach, Laternen und Feuer flackern im Wind, Fahnen und Schilder schwingen stärker (haben schon Schwingteile).
- Lagerfeuer: im Regen zischt es, kleinere Flammen, Dampf; unter Dach unverändert.
- Fluss und Angeln: Regen färbt das Wasser trüber, Fische beissen im leichten Regen besser, im Gewitter gar nicht oder nur scheue Tiefennacht-Fische (Faktor `weather` in `FishingRules`), Wurfweite im Sturm kürzer.
- Alchemie: Regenwasser/Tau als Zutat (`dew` gibt es, `rain` wäre nach der Bedingung `condition_block` ein leichter Zusatz). Entscheidung offen.

Spielerische Folgen (Vorschlag, nicht ohne Rückfrage bauen):

- **Schleichen im Regen**: Regen und Wind übertönen Schritte (Hörreichweite der Zuhörer x0.7), Sicht etwas kürzer. Das macht Regen zu einer taktischen Chance statt zu einer Strafe.
- **Sturmnacht** als neue besondere Nacht (`NightRules` special `storm`, ab Tag 6): Blitze enthüllen kurz Silhouetten und Augen der Schattenwesen, Donner überdeckt ihre Geräusche, Stadtlicht flackert. Der bestehende Nebel (`fog` special) wird zur Wetterlage `fog`.
- Geringer Bonus durch Regen: Heilpflanzen wachsen schneller (nur über die bestehende Nässe).
- Nichts, was Gegenstände zerstört, Hunger/Durst einführt oder Zeit stiehlt. Kein Auskühlen, kein Blitzschaden.

## 10. Technik

### 10.1 Bausteine

| Baustein | Ort | Aufgabe |
|---|---|---|
| `WeatherRules` | `src/systems/weather_rules.gd`, rein | Segmentkette, `state_at(seed, epoch)`, Blitzzeiten, Zusammenfassungen (`ground_wet`, `rain_total`), testbar ohne Szene |
| `data/weather.json` | Daten | Lagen, Übergänge, Dauern, Tageszeit-Gewichte, Regionen, Story-Sperren, Klang, Obergrenzen |
| `WeatherField` | `src/world/weather_field.gd` | erzeugt die kachelbaren Rauschtexturen (Worker-Job über `Jobs`, am Start), `cloud_at(pos)`, `rain_at(pos)`, Drift; setzt die Shader-Globals |
| `WeatherManager` | `src/world/weather_manager.gd`, Knoten `Weather` von `WorldLevel`, Gruppe `weather` | Zeit lesen, glätten, Host-Override (`force`, Dev-Menü), Signale (`changed`, `thunder`), `sunlight()`, `rain_here()` für Verbraucher |
| `WeatherSky` | `src/world/weather_sky.gd` | Wolken-Quad, Regen-Quad, Blitzlicht (Vollbild-Ebenen unter dem HUD, Layer 0) |
| `weather_clouds / weather_rain / weather_lightning.gdshader` | `assets/shaders/` | Darstellung |
| `weather_noise.gdshaderinc` | gemeinsam | Textur-Lesen identisch zur CPU |
| `WeatherAudio` | `src/world/weather_audio.gd` | Betten, Regen unter Material, Donner mit Verzögerung |
| `RainSplash` | `src/fx/rain_splash.gd` | Boden-/Wasserspritzer, Pfützen |

### 10.2 Shader-Globals (neu, in `project.godot` unter `[shader_globals]`)

`g_cloud_tex`, `g_cloud_drift` (vec2), `g_cloud_cover` (float), `g_rain` (lokale Regenstärke), `g_storm`, `g_wet` (Bodennässe), `g_light_scale` (Sonne x Wetter). Bestehende: `g_sun` (wird bereits mit Wetter multipliziert ausgegeben), `g_dew`, `g_night`, `g_wind_*`.

### 10.3 Multiplayer und Speichern

- Das Wetter wird nirgends gespeichert und nirgends repliziert. Jeder Peer rechnet `WeatherRules.state_at(Moisture.world_seed, epoch)`. Der Host sendet nur Overrides (`_rpc_force(id, seconds)` für Entwickler/Story) und für Beitretende den aktuellen Override.
- Blitz-/Donnerzeiten sind ebenfalls reine Funktion der Zeit, nicht des Klientenzustands.
- Einzig die Gameplay-relevanten Abfragen (z. B. Hörreichweite, Fischen) laufen auf dem Host mit demselben `WeatherRules` und sind deshalb ohne Abgleich konsistent.
- Pausierbar: alle Uhren hängen am Spiel (`PROCESS_MODE_PAUSABLE`), Zeitlupe läuft mit, wie `WorldWind`.

### 10.4 Leistung

- Vollbild-Shader sind teuer: Wolken und Regen in **einem** Quad zusammenfassen, bei `cloud`/`rain` nahe 0 früh abbrechen und das Quad ausblenden (`visible = false`). Zielbudget < 1.2 ms bei 640x360 internen Pixeln.
- Rauschtextur 256x256 R8 (und 128x128 für Detail) einmal pro Start, Erzeugung auf einem Worker (`Jobs`), keine Schicht pro Chunk.
- Boden-Spritzer und Pfützen: harte Obergrenzen (60 Spritzer, 12 Pfützen im Bild), nur nahe der Kamera.
- Keine Lichter pro Tropfen; Blitz ist eine einzelne additive Fläche.
- `Moisture` bleibt API-kompatibel, wird aber aus dem Wetter gespeist; bestehende Verbraucher (`PlantSowing`, `LeafCritter`, `_grow_things`) brauchen keine Änderung.

### 10.5 Pixelrichtlinien

Ganzzahlige Pixel, Tropfen 1 px breit, Wolkenränder gedithert, kein Alpha-Blur. Unlit/weltverankerte Teile folgen den Regeln aus `docs/design_guide.md` Abschnitt 6 (nur Eigenleuchtendes ist ungetönt). Der Regen wird **nach** `DayNight` getönt gezeichnet (er soll in der Nacht dunkel sein), Blitzlicht additiv.

## 11. Umsetzung in vier Schritten

Jeder Schritt liefert etwas Sichtbares, ist für sich testbar und hängt nur von den vorigen ab.

### Schritt 1 – Wetterkern, Wolken und Wolkenschatten (Sonne / bewölkt)

- `WeatherRules` (Segmentkette, Zustände, reine Tests: Stetigkeit über Mitternacht, Determinismus pro Seed, Verteilung, Zeitsprünge) und `data/weather.json`.
- `WeatherManager` im Level, Glättung, Entwickler-Override, Anzeige des aktuellen Wetters (ENTWICKLER-Tab: Wetterlage wählen, Zeitraffer, Wetter-Name).
- `WeatherField`: Rauschtexturen, CPU-Spiegel, Drift, Globals.
- Sichtbare Wolken (`weather_clouds`), neue Wolkenschatten in `daylight.gdshaderinc` (und `ground_tone`/`DayMotes` über den gemeinsamen Pfad), `DayNight` multipliziert Sonne/Gold/Tau und Mondlicht mit dem Wetter, `MoodGrade` bekommt Bedeckt-Anpassung.
- Wind: `WorldWind.strength` aus dem Wetter (still/normal/windig; Sturm später voll).
- Ton: leise Windbett-Variation (noch kein Regen).
- Ergebnis: sonnige, heitere, wolkige und bedeckte Tage mit ziehenden echten Wolken und Schatten, Test `tools/test_weather.tscn` (Regeln, Texturparität CPU/GPU, Schattenbild bei Lagen) und Aufnahmen `tools/preview_weather.tscn`.

### Schritt 2 – Regen und nasse Welt

- `weather_rain`: drei Tiefenschichten, Windneigung, Böen-Schleier, Unterstand über die Kronenmaske, Innenraum aus.
- `RainSplash` (Boden, Wasser), Regenringe im Wasser-Shader, `g_wet` im Boden (nasser Ton, Glanz), Pfützen, Dampf/Sonnenstrahlen nach dem Regen.
- Ellie wird nass, Fussabdrücke/Schritte auf nassem Grund, Regen-Betten, Innenraum-Dachregen und Tropfen (Hütte, Kabine mit Loch im Dach).
- `Moisture` aus dem Wetter, Pflanzen/Pilze reagieren (bestehende Hooks).
- Nieselregen, Regen, Starkregen mit sichtbarer Regenzelle (Vorhang unter dunkler Wolke).
- Test `tools/test_weather_rain.tscn` (Dichte-/Neigungsmessung gegen den Wind, Unterstand, Innenraum, Obergrenzen) und Aufnahmen.

### Schritt 3 – Sturm und Gewitter

- Windstärke bis Sturm, Böenhäufigkeit, Richtungsdrehung bei Fronten, Vegetation/Kronen/Fahnen/Laternen stärker, Treibgut-Partikel (Budget hoch, neue Arten).
- Gewitter: Blitz (Zeitscheiben-Funktion), Vollbild-Flash, gezackter Pfad, Donner mit Verzögerung, Böenwand, dunkler Himmel.
- Starkregen im Wind (fast waagerecht), Wellen/Schaum auf Gewässern, Wasserlärm, Kronen-Rauschen.
- Regionale Färbungen (Leere, Hexenwald) und Weltrand-Regen.
- Test `tools/test_weather_storm.tscn` (Böenmessung, Blitzzeiten identisch auf zwei Peers, Obergrenzen) und Aufnahmen.

### Schritt 4 – Lebendige Welt, Spielbezug, Feinschliff

- Tiere, Siedler, Pflanzen, Feuer reagieren (Abschnitt 9, kosmetischer Teil); Angeln und Alchemie lesen das Wetter.
- Entscheidungen aus Abschnitt 12 umsetzen (Schleichen im Regen, Sturmnacht, Regenwasser).
- Wetter-Anzeige (kleines Symbol an der `ClockVine`, Einstellungsoption `WETTER-EFFEKTE` Aus/Reduziert/Voll für Leistung und Zugänglichkeit, Blitz-Reduktion für lichtempfindliche Spieler).
- Karte: Wetterzug in der Karte nicht angezeigt (nur eine kleine Notiz im Stadt-Tab), Wettervorhersage-Idee prüfen.
- Mehrspieler-Test (zwei Prozesse, gleiche Blitz-/Wolkenbilder), Leistungsmessung, Audio-Mischung, Dokumentation und CLAUDE.md-Eintrag.

## 12. Offene Entscheidungen (für dich)

1. **Wetter auf der Karte/Vorhersage?** Ein Wetterwechsel ist aus der Weltzeit vorhersagbar (reine Funktion). Soll es eine Ankündigung geben ("Dunkle Wolken ziehen auf"), eine Vorhersage im Stadt-Tab oder gar nichts?
2. **Spielerische Folgen**: nur Stimmung, oder auch Schleichen im Regen, Sturmnacht, Regenwasser-Zutaten (Abschnitt 9)?
3. **Blitzeinschläge**: nur Optik, oder später echte Gefahrenzonen (angekündigt, ausweichbar) mit Funken und Brand an Bäumen?
4. **Klima der Regionen**: soll jedes Gebiet sein eigenes Wetterverhalten bekommen (Leerenblühen, Hexenwald)? Der Startstand lässt die Daten leer.
5. **Wetter im ersten Spielabschnitt**: Heiter erzwungen bis zur Hütte (Vorschlag) oder darf der Hinterhalt/die Hütte schon Wetter haben?
6. **Schnee** oder andere Wetterarten für spätere Gebiete? Das System ist dafür vorbereitet (zusätzliche Lage + Partikelart), wird aber jetzt nicht gebaut.
7. **Regenbogen**: In der 3/4-Ansicht kaum lesbar; Vorschlag: statt eines Bogens nur kräftige Lichtstrahlen und Dampf nach dem Regen.

## 13. Abnahme

- Mehrere Spieltage hintereinander (F4 auf Zeitraffer) zeigen eine plausible Abfolge ohne harte Sprünge; dieselbe Folge nach Neustart mit gleichem Seed.
- Wolkenschatten gehören zu sichtbaren Wolken (Versatz stimmt), Regen fällt wie die Gräser wehen.
- Unter Kronen und in Innenräumen regnet es nicht oder dünn; die Hütte klingt nach Regen auf dem Dach.
- Zwei Peers sehen dasselbe Wetter, denselben Blitz zur selben Zeit.
- Figuren, Kampfzonen, Dialoge, Interaktionsprompts bleiben bei Starkregen und Sturm lesbar.
- Leistung: Wolken + Regen + Sturm < 1.2 ms zusätzlich, keine neuen Spitzen beim Chunk-Streaming.
- Pause, Zeitlupe, Menü, Karte, Dialog: Wetter pausiert bzw. blendet Partikel aus wie `WorldWind`.

## 14. Umsetzungsstand (2026-11-10)

**Gebaut (alle vier Schritte in einem Zug):**
- Kern: `WeatherRules` (Markov-Kette aus Seed + Weltzeit, 10 Zustände, Blend, Hexenwald-Klima, ruhiger Start `calm_until` 3 Tage), `WeatherField` (eine 128²-Rauschtextur, GPU und CPU lesen dieselben Texel), `WeatherManager` (Glättung 1,4 s, Shader-Globals, Wind, Blitz/Donner-Zeitleiste, Override per RPC `force`), Daten `data/weather.json`.
- Himmel: `WeatherSky` (drei Screen-Ebenen unter dem HUD) mit `weather_clouds` (Wolken aus demselben Feld wie ihre Schatten, Versatz je nach Sonnenstand), `weather_rain` (drei Tiefenlagen, vom Wind geschert, Schleier, Nebelbänke, Kronentropfen), `weather_flash` (Blitz, Bolzen, Wetterleuchten, Farbe grün im Hexenwald / magenta an der Leere).
- Boden: nasser Ton, Pfützen mit Himmelsspiegel und Ringen, Spritzer (in `ground_tone.gdshader`, also unter Objekten); `Moisture` hängt am Wetter.
- Wind: `WorldWind.set_weather` (Stärke, Richtung, Böen bis ~2,5, Trümmer-Partikel im Sturm, Budget).
- Licht: `DayNight` multipliziert Sonne/Goldene Stunde/Tau mit `sunlight()`, dämpft die Tagesfarbe (`ambient_dim`).
- Spielwelt: Spielerin wird im Regen nass (nicht unter Kronen/Dächern), Alarmradius der Schattenwesen sinkt in Regen/Gewitter (`StealthComponent.alarm_scale`), Angeln (leichter Regen belebt, Sturm drückt), Spezialnacht `storm`, Tropfen in kaputten Dächern schneller, Schmetterlinge/Bienen/Marienkäfer ruhen im Regen, Glühwürmchen löschen, Sonnenblume schließt sich.
- Ton: `tools/audio_weather.py` -> `assets/audio/weather/` (3 Regenbetten, Dach, 2 Windbetten, 3 Donner), `WeatherAudio` mit Bus „Weather“ + Tiefpass (innen ~700 Hz, unter Kronen ~3 kHz).
- UI: Dev-Tab ENTWICKLER (Wetter-Buttons), Einstellungen WETTER-EFFEKTE (AUS/REDUZIERT/VOLL) und BLITZE SANFT, Wetterwort unter der Uhr (nicht bei klar/heiter).
- Tests: `tools/test_weather.tscn` (28 Prüfungen, `WEATHER OK`), Captures `tools/preview_weather.tscn -- --dir=/abs --states=...`.

**Noch offen:** Siedler/Dorf suchen bei Regen noch keinen Unterschlupf, Lagerfeuer zischt nicht, Fahnen/Laternen reagieren nicht gesondert auf Sturm, Regenwasser-Zutat, Ernte-/Pflanzenwachstum, Wasserringe im Fluss-Shader (`river_water`), Mondlicht unter Wolken (`night_moon`), nasse Sprites/Gebäude (`day_sprite`), Spezialnacht-Hinweis-Text im Regen. Optik und Mischung (Wolkendeckkraft, Regendichte, Pfützengröße) sind nach ersten Captures eingestellt, aber nicht im laufenden Spiel über Tage abgenommen.
