# 📜 Voidbloom / Shadowspore – Update-Log & Changelog

Alle Änderungen, neuen Features, Rebalancing-Werte und technischen Anpassungen chronologisch sortiert.

---

## [V0.7.0 Beta] – 2026-11-11
### 🌾 Ernte, Sturm & Spiegelscherben: Ackerbau, Dynamische Wetterfronten, Schwarzes Brett, Boss Morwenna & Leere-Alchemie

![Die Spiegelhexe Morwenna](docs/img/morwenna.png)

> 📜 ***Aus einem durchnässten Brief von Gustav an der Dorfpforte:***  
> *„Wer hätte gedacht, dass aus dem Schlamm dieser einsamen Lichtung einmal etwas sprießen würde? Die ersten Beete sind gehackt, und der Knollenkeim streckt zarte Blätter dem Himmel entgegen. Doch blickt nach Süden, Freunde... Über dem Hexenwald braut sich ein Sturm zusammen. Der Himmel verfärbt sich giftgrün, Blitze zucken durch die Ulmen und die Raben kreischen wie besessen um ihren alten Baum. Haltet eure Gießkannen bereit, wetzt die Sicheln und werft einen Blick auf das neue Schwarze Brett am Dorfplatz – es gibt viel zu tun, ehe die Nacht hereinbricht!“*

---

> [!WARNING]
> **Wetterwarnung & Sturmnacht:**  
> Bei Starkregen und Gewitter dunkelt die Welt merklich ab. Regentage wässern eure Felder zwar automatisch, doch im Schutz des Donnergrollens schleichen Schattenkreaturen leiser heran. Bringt eure Ernte rechtzeitig ins Trockene!

> [!TIP]
> **Taktiker-Hinweis zur Ernte:**  
> Wer seine Beete ununterbrochen jede Nacht wässert, erhält bei der Ernte den begehrten *Pflege-Bonus* (+1 zusätzlicher Ertrag). Wundblatt-Pflanzen müssen nach dem Pflücken nicht neu gesät werden – sie wachsen von selbst alle zwei Nächte nach!

---

### 🌟 Die Großen Highlights

#### 1. 🌾 Ackerbau & Farming-System (Die Kategorie ACKER)
Die Selbstversorgung des Dorfes erreicht eine völlig neue Dimension: Gustav schaltet nach der Fertigung der ersten Werkzeuge die neue Bau-Kategorie **ACKER** frei!

* **Scholle brechen mit der Hacke:** Mit der geschmiedeten Hacke brecht ihr den rohen Erdboden in gehackte Ackerfurchen auf. Durch mehrmaliges Harken hält die Furche länger vor dem Verwildern.
* **Dynamische Feld-Verschmelzung:** Platzierte 3x3-Felder verschmelzen an den Kanten nahtlos miteinander zu zusammenhängenden Großäckern mit bröseligen Rändern und feinen Krümeln.
* **Wildsamen & Aussaat:** Beim Pflücken von Wildpflanzen erhaltet ihr nun wertvolles Saatgut:
  * **Knollenkeim (45 % Chance bei Erdknollen):** Gedeiht in 4 Nächten zu 2–3 schmackhaften Knollen.
  * **Glutmöhrensamen (50 % Chance bei Glutbeeren):** Wächst in 5 Nächten heran und leuchtet bei Nacht mit feurigem Glanz auf dem Feld.
  * **Nachtrübensamen (50 % Chance bei Nachtrüben):** Reift in 6 Nächten zu schimmernden Rüben heran.
  * **Wundblattsamen (40 % Chance bei Wundblättern):** Benötigt nur 3 Nächte und wächst danach alle 2 Nächte automatisch nach!
* **Gießen & Feuchtigkeits-Glanz:** Mit der Gießkanne versorgt ihr die Saat mit lebenswichtigem Wasser. Nasse Erde färbt sich tiefdunkel und glitzert in der Sonne. Nur gewässerte Beete wachsen über Nacht weiter.

<details>
<summary>📖 <b>Farming-Almanach: Wachstumszyklen & Pflege (Klicken zum Entfalten)</b></summary>

| Feldfrucht | Saatgut | Wachstumsdauer | Ertrag | Besonderheit |
|---|---|---|---|---|
| **Erdknolle** | Knollenkeim | 4 Nächte (1-1-2) | 2–3 Knollen | 35 % Chance auf Samenrückgabe |
| **Glutmöhre** | Glutmöhrensamen | 5 Nächte (1-2-2) | 1–2 Möhren | Leuchtet nachts auf dem Acker |
| **Nachtrübe** | Nachtrübensamen | 6 Nächte (2-2-2) | 1–2 Rüben | Hohe Nährkraft für Alchemie |
| **Wundblatt** | Wundblattsamen | 3 Nächte (1-1-1) | 1–2 Blätter | Wächst alle 2 Nächte nach (`regrow`) |

</details>

---

#### 2. ⛈️ Dynamisches Wettersystem & Himmelsdynamik
Das Wetter zieht als lebendige Kraft über Shadowspore und formt Umwelt, Sicht und Gameplay.

* **10 Dynamische Wetterlagen:** Von strahlendem *Klar* und sonnigem *Heiter* über *Nieselregen*, gleichmäßigen *Regen*, prasselnden *Starkregen*, peitschenden *Sturmwind* bis hin zu dichten *Nebelbänken* und tosenden *Gewittern*.
* **Räumliche Wolkenfelder & wandernde Schatten:** Echte Wolkendecken treiben mit der Windrichtung über die Kontinente und werfen scharfe, wandernde Wolkenschatten auf Wiesen und Klippen.
* **Atmosphärische Gewitter & Blitze:** Bei Unwettern zucken reale Blitze vom Himmel, erhellen für Sekundenbruchteile das Land und lassen Doppelblitze aufzucken. Im Hexenwald leuchten Blitze in giftigem Smaragdgrün!
* **Unterstand & Lebenswelt:** Dichte Baumkronen spenden natürlichen Regenschutz. Flüsse und Seen bilden Regenkringel, und Regentage gießen automatisch jedes angelegte Feld im Dorf!
* **Einfluss auf die Jagd:** Starkregen und Sturm dämpfen Geräusche (Monster-Alarmreichweite sinkt um bis zu 40 %), während seltene Gewitterfische bei Unwetter an die Wasseroberfläche drängen.

---

#### 3. 📋 Das Schwarze Brett (Quest-Tafel im Dorf)
Auf dem Dorfplatz kann nun das monumentale **Schwarze Brett** (`quest_board`) errichtet werden.
* **Bürger-Aufträge & Kopfgelder:** Anschläge von Gustav, Valdric und Torben bieten Belohnungen für Ressourcenlieferungen, Monsterjagden und Erkundungen.
* **Fortschritt & Aushänge:** Neue Zettel und Pergamente flattern dynamisch im Wind und informieren über anstehende Events und Welt-Meilensteine.

---

#### 4. 🪞 Voll spielbar: Bosskampf gegen Morwenna, die Spiegelhexe
Der zweite Story-Boss erwacht im Schieferkessel am Großen Rabenbaum zu vollem Leben!

* **Vollständiges 3-Phasen-Gefecht:**
  * **Phase 1:** Harzschnitt-Kombos, wendige Schatten-Finten und zeitversetzte Wurzelspeere aus dem Boden.
  * **Phase 2 („Der Spiegel zerbricht“):** Zersplitterung der Maske, Scheren-Zangenangriffe und erste permanente Glitch-Klone, die im Takt mit Morwenna zuschlagen.
  * **Phase 3 („Die Hexenstunde“):** Morwenna entfesselt zwei Klone gleichzeitig, sperrt das Areal mit Fluchspiegel-Käfigen ab und startet rotierende Karussell-Angriffe.
* **Die Raben als Verbündete:** Fliegt Morwenna im Glitch-Swap auf eine andere Position, kreischen die Raben in den Baumkronen zielsicher über dem echten Original!
* **Legendäre Beute:** *Moras Spiegelscherbe* (`mora_shard`) für Alchemie und Veredelung sowie Replay-Hologramm zur Wiederholung des Kampfes.

---

#### 5. 🧪 Erweiterte Alchemie: Spezial- & Leere-Sude
Esmas Kessel im Hexenwald bietet ab sofort Zugriff auf 4 mächtige Spezial-Tranklinien in je 3 Reifegraden:
* **Aschenhaut (I–III):** Reduziert erlittenen Feuerschaden um 40 % bis 60 %; Stufe III macht 60 Sekunden lang völlig immun gegen brennenden Boden.
* **Klarblick (I–III):** Bis zu 120 Sekunden absoluter Schutz vor Halluzinationen im Nebel; Pflückpflanzen funkeln golden und Schattenmonster verraten sich durch glühende Augen.
* **Irrlichtsud (I–III):** Beschwört ein treues Irrlicht herauf, das die Dunkelheit bannt und Schattenmonster zurückscheucht (steigert im Gegenzug die Aufmerksamkeit der Nacht).
* **Leere-Trank (I–III):** Reißt für bis zu 7 Sekunden eine Mini-Leere um Ellie auf – massiver Void-Schaden gegen umstehende Feinde mit bis zu 75 % Lebensraub!

---

#### 6. ⚔️ Animationen & Gameplay-Feinschliff
Alle Charakter-Animationen wurden von Grund auf überarbeitet und auf maximale Flüssigkeit poliert.

![Flüssige Schwertkombo](docs/img/ellie_combo_before_after.gif)

* **Dynamischer Vorher-Nachher-Sprung:** Ob Laufen, Sprinten, Schleichen, Brustschwimmen, Kraulen oder die 5-Stufen-Schwertkombo – Übergänge greifen geschmeidig ineinander.
* **Präzises Hit-Feedback:** Schläge fühlen sich wuchtiger an, Waffenschweife ziehen sauber durch die Luft und Trefferzonen passen sich pixelgenau an.

---

### ⚖️ Balance & Spielwerte auf einen Blick

| Status | Bereich / Parameter | Vorher | Jetzt (V0.7.0) | Auswirkung im Spiel |
|---|---|---|---|---|
| 🟣 `NEU` | **Ackerbau-Kategorie ACKER** | Keine | **Freischaltbar bei Gustav** | Felder, Hacke, Gießkanne & 4 Saatgut-Arten |
| 🟣 `NEU` | **Ernte-Pflegebonus** | – | **+1 Extra-Ertrag (`ripe_bonus`)** | Belohnt tägliches Wässern ohne Aussetzer |
| 🟣 `NEU` | **Wundblatt-Nachwachsen** | Einmalige Ernte | **Alle 2 Nächte (`regrow: 2`)** | Dauerhafte Heilkräuterquelle auf dem Acker |
| 🟣 `NEU` | **Dynamisches Wettersystem** | Starres Licht | **10 Wetterlagen & ziehende Wolken** | Von Sonnenschein bis Unwetter mit Blitzen |
| 🟢 `BUFF` | **Feld-Bewässerung bei Regen** | Manuell mit Kanne | **100 % automatisch gegossen** | Regentage sparen Zeit und Gießkannenschwünge |
| 🟢 `BUFF` | **Schleichen bei Unwetter** | 100 % Alarm | **Bis zu -40 % Alarmreichweite** | Monster hören Schritte bei Regen und Sturm schlechter |
| 🟣 `NEU` | **Gewitter-Angeln** | Standardfische | **Spezielle Gewitter-Beißrate (0.85)** | Seltene Fische drängen bei Sturm an die Oberfläche |
| 🟣 `NEU` | **Schwarzes Brett (Dorf)** | – | **Errichtbar für Quests & Kopfgelder** | Zentraler Anlaufpunkt für Bürger-Aufträge |
| 🟣 `NEU` | **Bosskampf Morwenna** | Nur Konzept | **Vollständig spielbar (3 Phasen)** | Glitch-Klone, Klon-Tausch & Spiegelscherben |
| 🟣 `NEU` | **Spezial-Tränke (4 Linien)** | Nur Heilung/Ausdauer | **Aschenhaut, Klarblick, Irrlicht & Leere** | Bis zu 75 % Lebensraub und Feuer-Immunität |
| 🟢 `BUFF` | **Charakter-Animationen** | Starre Frames | **Komplett geglättete Animations-Loops** | Spürbar flüssigeres Laufen, Schwimmen & Kämpfen |

---

### 🔮 Sneak Peek: Was erwartet euch als Nächstes?
*„Unter dem tiefen Grollen der Gewitterfront hallt ein metallischer Klang aus dem Westen wider. Gustav hat alte Grubenpläne entrollt, und Torben bereitet schwere Spitzhacken vor: Das Tor zu den **Alten Tiefenminen** steht kurz vor der Öffnung... Macht eure Laternen bereit!“*

✦ ──────────────── ❖ ──────────────── ✦  
*Mit leuchtenden Sporen und geschärften Klingen,*  
**Euer Shadowspore-Entwicklerteam 🌿⚔️**

---

## [V0.6.2 Beta] – 2026-11-10
### 🪞 Echo der Zerrissenen: Boss-Enthüllung Morwenna, Höhenstufen-Verdeckung, Mornath-Arena-Polishing & Kampffeinschliff

![Der Hexenturm und die Nebelhexe](docs/img/witch_tower_site.png)

> 📜 ***Aus den Warnungen des alten Kriegers Valdric an der Schwelle zum Schieferkessel:***  
> *„Ellie... sieh dir das Siegel an jener zerbrochenen Klinge am Fuße des Rabenbaums an. Das dort in der Mulde ist kein gewöhnliches Ungeheuer des Forsts. Das ist Morwenna... die Großhexe des Alten Zirkels, von der die Chroniken berichten! Sie fiel damals nicht im Großen Riss – sie versuchte, ihre zerfallende Seele in das unsterbliche Herzholz des Baumes zu binden. Doch die Leere fraß ihren Zauber mitten im Vollzug. Sie existiert in einem ewigen, schmerzhaften Zerrissenwerden – und saugt dem Heiligtum der Raben die pure Lebenskraft aus. Tretet ihr nur mit klarem Geist und geschärfter Klinge entgegen...“*

---

> [!WARNING]
> **Gefahr am Schieferkessel:**  
> Morwenna bedient sich unberechenbarer Glitch-Klone und blitzartiger Scheren-Angriffe. Wenn sie Spiegelscherben heraufbeschwört, lauscht den Rufen der Raben in den Wipfeln – sie kreisen nur über der *echten* Hexe!

> [!TIP]
> **Taktiker-Hinweis zur Höhenstufe:**  
> Dank des neuen Höhenstufen-Systems könnt ihr Klippenkanten nun gezielt nutzen, um feindlichen Geschossen zu entgehen. Beachtet jedoch, dass höher gelegene Felsplateaus Angreifer unterhalb verbergen können.

---

### 🌟 Die Großen Highlights

#### 1. 🪞 Boss 2: Morwenna, die Spiegelhexe (Die Zerrissene)
Mit Morwenna betritt der zweite monumentale Story-Boss die Welt von Shadowspore! Ihr Treiben im Schieferkessel des Hexenwalds bedroht das gesamte Gefüge der Region.

![Der monumentale Krähenbaum im Schieferkessel](docs/img/crow_tree.png)

* **Die Tragödie des gescheiterten Wandels:** Morwenna existiert in einem permanenten, instabilen Transmutations-Limbus zwischen physischer Materie und Leere. Ihr Leib wird nur noch durch die Lebenskraft des uralten Rabenbaums zusammengehalten.
* **Unberechenbares Glitch-Verhalten:**
  * **Micro-Stutter & Spasmen:** Nach heftigen Schlägen friert ihr Körper kurzzeitig in knisternden Standbildern ein oder zuckt unwillkürlich zur Seite.
  * **Zweistimmigkeit:** Morwennas Stimme ist gedoppelt – eine erhabene Hexe überlagert von einem schneidenden Void-Echo.
  * **Permanente Scanline-Klone:** Flüchtige Raum-Fragmente ihrer Existenz unterstützen sie im Kampf. Sie besitzen keinen Bodenschatten und lösen sich bei Treffern in Nebel auf.
  * **Glitch-Swap:** Morwenna kann jederzeit blitzschnell die Position mit einem Klon tauschen *(Achtet auf die kreisenden Raben – sie markieren das Original!)*.
* **Mehrphasiger Gefechtsverlauf:**
  * **Phase 1 (100 % – 66 % HP):** Rasende Zick-Zack-Sprints, 3-teilige Harzschnitt-Kombos, Wurzelspeere aus dem Lehmboden und verlangsamender Fluchsaft.
  * **Phase 2 (66 % – 33 % HP – „Der Spiegel zerbricht“):** Eine Druckwelle schleudert Angreifer zurück; Morwennas Gesichtsmaske zersplittert. Erste permanente Glitch-Klone spalten sich ab, Scheren-Zangenangriffe und an Schieferfelsen abprallende Spiegelscherben setzen euch zu.
  * **Phase 3 (33 % – 0 % HP – „Der Schrei des Rabenbaums“):** Morwenna zapft die Hauptwurzeln an. Der gesamte Kessel gerät in Flammen; Fluchspiegel-Käfige sperren den Bewegungsraum ab, während sie zum finalen Vernichtungsschlag ausholt.

<details>
<summary>📖 <b>Boss-Dossier: Morwenna, die Spiegelhexe (Klicken zum Entfalten)</b></summary>

| Eigenschaft | Detail |
|---|---|
| **Klassifizierung** | Gefallene Großhexe / Instabiles Void-Phänomen (Boss 2) |
| **Arena & Ort** | Schieferkessel am Großen Rabenbaum (Hexenwald, Tile 879, 914) |
| **Waffen** | Zwei verrostete Zeremonien-Sicheln aus Fluchsilber |
| **Schwachstelle** | Micro-Stutter nach schweren Scheren-Hieben; Klon-Entlarvung über die Raben |
| **Phasen-Schwellen** | Phase 1 (100 %), Phase 2 (66 %: Spiegelbruch), Phase 3 (33 %: Wurzel-Entfesselung) |

</details>

---

#### 2. 🏔️ Höhenstufen-Verdeckung & Klippenschatten (Elevation Occlusion)
Die räumliche Tiefe der Spielwelt wurde grundlegend modernisiert:
* **Echte visuelle Klippenüberhänge (`ReliefOverhang`):** Wenn Spielfiguren, Gegner oder Gegenstände südlich unterhalb einer Felskante stehen, werden sie nun physikalisch und perspektivisch korrekt von der Felswand überdeckt (`z_index = 1`).
* **Schattenwurf an Felswänden:** Höhere Plateaus werfen saubere Schattensäume auf die darunterliegenden Wiesen und Schieferböden.
* **Präzisierte Kletterkanten:** Die Erkennung von `WallClimb` richtet sich nun exakt nach den vertikalen Felsstufen aus.

---

#### 3. ⚔️ Mornath-Arena-Polishing & Schockwellen-Rework
Der Kampf gegen den Himmelsspalter Mornath in der Feuerarena wurde visuell und spielmechanisch auf Hochglanz poliert:
* **Schockwellen-Geometrie (`ShockRing`):** Vollständig überarbeitete Schockwellen mit dynamischer Segmentierung, optischen Bodenverzerrungen und pixelgenauer radialer Schadensabfrage.
* **Stabile Brandfelder (`PixelFlames`):** Brennende Arenazonen flackern ruhiger, besitzen optimierte Partikelraten und verursachen verlässlichen, synchronisierten Flächenschaden.
* **Leerenbarrieren (`RiftWall`):** Geschärfte Partikelränder und glasklare Begrenzungslinien während der Phasenwechsel.

---

#### 4. 🎯 Kontextsensitiver Cursor & Schadenszahlen-Overhaul
* **Dynamische Cursor-Glyphen:** Das Fadenkreuz passt sich nun automatisch der Spielsituation an:
  * 🏹 Fernkampf-Visier beim Spannen von Bögen
  * ✋ Greifhand an erntebaren Pflanzen und Kisten
  * 🪶 Feder-Symbol bei der Annäherung an zähmbare Vögel
  * 🧗 Klettersymbol an besteigbaren Felswänden
  * 🗡️ Geschärfter Kampffokus im Nahkampf
* **Schadenszahlen mit Flugparabel:** Zahlen steigen nicht mehr starr nach oben, sondern federn in sanften Bögen zur Seite. Kritische Treffer pulsieren hervorgehoben und sind farblich nach Schadenstyp codiert.

---

#### 5. 🐾 Lebendige Wildnis & Untergrund-Reaktionen
* **Reaktives Tierverhalten:** Bären, Kaninchen und Krähen reagieren nun sensibel auf Fackellicht, die Nachtphasen des `NightDirector` und nahe Bosskämpfe.
* **Materialspezifische Schritt-Effekte:** Die Schritt-Komponente erkennt den genauen Untergrund (Gras, Schiefergestein, Holz, flaches Wasser, Matsch) und erzeugt darauf abgestimmte Staubwölkchen, Gischt oder Schlammspritzer.

---

#### 6. 🌌 Atmosphärischer Abgrund-Rand (Void Edge)
* Die äußeren Grenzen der schwebenden Inseln wurden optisch aufgewertet: Brodelnde Leere-Zungen und schwebende violette Partikel säumen die Klippen und warnen vor dem bodenlosen Fall.

---

### ⚖️ Balance & Spielwerte auf einen Blick

| Status | Bereich / Parameter | Vorher | Jetzt (V0.6.2) | Auswirkung im Spiel |
|---|---|---|---|---|
| 🟣 `NEU` | **Boss 2: Morwenna** | – | **Vollständiges Boss-Dossier & Kampf** | 3-Phasen-Gefecht mit Glitch-Klone-Mechanik |
| 🟣 `NEU` | **Klippen-Verdeckung** | Flache 2D-Überlagerung | **Echte Höhenstufen (`ReliefOverhang`)** | Felsvorsprünge verdecken Figuren darunter korrekt |
| 🟡 `REWORK` | **Schockwellen (`ShockRing`)** | Starre Kreise | **Dynamisch segmentierte Ringe** | Präziseres Ausweichen und sauberes Hit-Feedback |
| 🟢 `BUFF` | **Feuerarena-Brandflächen** | Instabile Flackerticks | **Geglättete Partikel- & Schadensraten** | Flüssigere Bildrate und verlässlicher Flammenschaden |
| 🟣 `NEU` | **Cursor-Zustände** | Statischer Standard-Zeiger | **5 kontextsensitive Glyphen** | Direktes optisches Feedback für Klettern, Fernkampf & Ernte |
| 🟡 `REWORK` | **Schadenszahlen** | Lineares Aufsteigen | **Bogenparabeln mit Crit-Popout** | Schnell lesbare Schadensspitzen im Gefecht |
| 🟢 `BUFF` | **Schritt-Partikel** | Einheitlicher Staub | **5 materialspezifische Fußspuren** | Sattes Feedback für Schiefer, Matsch, Holz & Wasser |
| 🟢 `BUFF` | **Kletter-Erkennung** | Gelegentliches Kantenwackeln | **Exakt ausgerichtete Klettervektoren** | Reibungsloser Auf- und Abstieg an Klippen |
| 🟣 `NEU` | **Abgrund-Effekte** | Harte Kante zur Leere | **Pulsierende Void-Zungen & Partikelfluss** | Deutlich atmosphärischere Weltgrenzen |

---

### 🔮 Sneak Peek: Was erwartet euch als Nächstes?
*„Tief unter den Wurzeln des Rabenbaums öffnet sich ein Schacht in die vergessenen Katakomben. Alte Schienen, verrostete Grubenloren und ein metallisches Hämmern im Dunkel kündigen das nächste Kapitel an: **Die Tiefenminen von Shadowspore** erwachen zum Leben...“*

✦ ──────────────── ❖ ──────────────── ✦  
*Mit leuchtenden Sporen und geschärften Klingen,*  
**Euer Shadowspore-Entwicklerteam 🌿⚔️**

---

## [V0.6.1 Beta] – 2026-11-10
### 🧙‍♀️ Hexenwald & Alchemie: Esma die Nebelhexe, Trankbrauen, Kletterranken, Dauerdämmer & der Wahn des Nebels

![Der Hexenturm und die Nebelhexe](docs/img/witch_tower_site.png)

*„Südlich der vertrauten Wiesen sinkt der Tag in ein bleiernes Halbdunkel. Wo das Gras fahl wird und uralte Schieferklippen aufragen, kriecht ein giftgrüner Dunst zwischen knorrigen Ulmen hervor. Ein gewundener Pfad führt tief in das Herz des Waldes – dorthin, wo eine einsame Hexe im Schatten ihres Turms den Kessel rührt und der Nebel den Verstand der Wanderer prüft...“*

---

### 🌟 Die Großen Highlights

#### 1. 🌲 Das neue Biom: Der Hexenwald (Region 31, Überregion 5)
Ein völlig neues, eigenständiges Gebiet setzt die Küste südlich der Stadt nahtlos fort – ohne Ladezeiten oder künstliche Barrieren (über 38.000 neue Tiles!).
* **Weicher Übergang:** Die Weltmaske dunkelt den Boden über 48 Tiles sanft ab; die Grasnarbe wechselt stufenlos in die kühle, dunkle Hexenwald-Palette (`BiomeBlend`).
* **Schiefer-Gelände & Klippen:** Dunkles Schiefer-Relief (Stil 5) mit 33 Rampen und Felsstufen.
* **Dauerdämmer:** Das Tageslicht wird im Wald spürbar gedämpft (Sonnenflecken und Lichtschäfte erlöschen, kühler Dunstschatten). Leuchtpflanzen glimmen mit mindestens 45 % Nachtstärke – auch zur Mittagszeit.
* **Der gewundene Pfad:** Ein geschwungener Stein- und Trampelpfad (`hexenwald_path`) führt von der Küstenwiese direkt zum Hexenturm im Waldzentrum.

---

#### 2. 🧪 Alchemie & Trankbrauen (Ablösung des Kochen-Systems)
Das bisherige Kochen wurde vollständig durch ein stimmungsvolles, tief integriertes **Alchemie-System** bei Esma der Nebelhexe ersetzt.

![Alchemie-Icons und Trankstufen](docs/img/alchemy_icons.png)

* **Kräuter & Pflanzen erhalten ihren Zweck:** Wundblätter, Alraunen, Glutbeeren, Geisterfarne und Mondglocken werden zu mächtigen Essenzen verarbeitet.
* **Zwei Tranklinien in 5 Leuchtstufen (I Trüb bis V Meistersud):**
  * **Heiltrank („Wundtau“):** Sofortige prozentuale Heilung der Maximalgesundheit (20 % bis 70 %) mit verlässlichem Mindestwert. Ab Stufe IV wird der Effekt *Verbrennen* sofort gelöscht; Stufe V wandelt Heilüberschüsse in schützende Überheilung um (10 s Wundpause zwischen Einnahmen).
  * **Ausdauertrank („Glutatem“):** Schenkt 30 Sekunden lang jede Sekunde frische Ausdauer (3 bis 12 Ausdauer/s) – und wirkt **auch während der Ausdauer-Regenerationspause**, beim Sprinten und im Angriff! Stufe IV/V verkürzen die Nachladepause drastisch; Stufe V senkt die Ausdauerkosten beim Sprinten um 15 %.
* **Viszerales Trinken:** Eigene Trink-Animation im Laufen und Kampf mit Soundkulisse (Korkenploppen, Gluckern, Heilen).
* **Brau-Enthüllung:** Animiertes Kesselfenster (`BrewReveal`) beim Entdecken und Brauen neuer Rezepturen.

---

#### 3. 🌫️ Giftgrüner Nebel, der Effekt HALLUZINIERT & die Phantom-Spinne
Der Hexenwald ist kein Ort, den man mit roher Waffengewalt bezwingt – er ist ein Ort, dem man nicht trauen kann.
* **Fortschreitender Trug (0..1):** Je länger man im Nebel verweilt, desto tiefer sinkt man in den Wahn:
  * **Stufe 1 (Flüstern):** Hexengrüne Augen glimmen im Dickicht, Schritte hallen hinter Ellie wider, Ulmen-Gesichter beobachten jede Bewegung.
  * **Stufe 2 (Trug):** Falsche Glitzer-Items lösen sich beim Aufheben in Rauch auf, falsche Silhouetten täuschen Wanderer, die Minimap-Aufdeckung wird blockiert, und das HUD zuckt mit Schein-Schaden.
  * **Stufe 3 (Wahn – Die Phantom-Spinne):** Täuschend echte Schattenspinnen brechen aus dem Boden hervor, pirschen heran und setzen zum Biss mit rotem Warnbereich an – **zerfallen aber im Moment des Einschlags spurlos zu Rauch!** Doch Vorsicht: Im Dauerdämmer pirschen vereinzelt auch echte Schattenwesen...
* **Schutz-Talisman – Klarglas-Ohrringe:** Trägerinnen erhalten den Perk *Klarer Blick* (`clear_sight`), der vor dem Effekt schützt und den Nebel um Ellie lichtet.

---

#### 4. 🏰 Der Hexenturm, Esma & der Krähenbaum
* **Der Hexenturm:** Ein monumentales Gebäude am Ende des Pfades mit Portal, Hof und animiertem Erkerfenster.
* **Esma, die Nebelhexe:** Vollständig animierte Bewohnerin mit eigener Kleidung, Gesten, Tag-Nacht-Rhythmus und Hexenkessel.

![Esmas Gesten und Animationen](docs/img/esma_gestures.png)

* **Der monumentale Krähenbaum:** Ein gigantischer Nistbaum im Wald (`crow_tree`), der als Zuflucht und Futterplatz für befreundete Krähen und Raben dient.

![Der Krähenbaum im Hexenwald](docs/img/crow_tree.png)

---

#### 5. 🧗‍♀️ Kletterranken & Schieferwände (Wall Climb)
* Steile Felswände sind kein Hindernis mehr: An rankenden Kletterpflanzen kann Ellie nun Felsstufen und Schieferklippen geschmeidig empor- und hinabklettern.
* Vollständiges Kletter-Animationsset (8 Richtungen, Hände am Fels, Verwundbarkeitsmasken).

---

#### 6. 🌿 Flora des Hexenwalds & Fluchsilber

![Flora und Rohstoffe des Hexenwalds](docs/img/hexenwald_flora.png)

* **Neue Bäume:** Knorrige Hexenulmen (`hag_tree`) und geisterhafte Bleichbäume (`bone_tree`).
* **Neue Pflanzenwelt:** Dornenhecken, Geisterfarne, Totenkerzen, Krötenkappen, Hexenhut-Pilze und ziehbare Alraunen-Wurzeln.
* **Neues Erz:** Fluchsilber-Felsen (`curse_rock`) mit grün glimmenden Erzadern und seltenem Fluchsilber-Erz.

---

### ⚖️ Balance & Spielwerte auf einen Blick

| Status | Bereich / Parameter | Vorher | Jetzt (V0.6.1) | Auswirkung im Spiel |
|---|---|---|---|---|
| 🟣 `NEU` | **Biom: Hexenwald** | Nicht vorhanden | **38.158 Tiles (Region 31)** | Neues zusammenhängendes Landgebiet mit Schieferklippen |
| 🟣 `NEU` | **Alchemie statt Kochen** | Altes Kochsystem | **Vollständiges Trankbrauen** | Nutzt Wundblätter, Alraunen & Beeren für Tränke I bis V |
| 🟣 `NEU` | **Heiltrank (Wundtau I–V)** | – | **20 % bis 70 % Max-HP** | Sofortheilung, Verbrennen-Löschung & Überheilung |
| 🟣 `NEU` | **Ausdauertrank (Glutatem I–V)**| – | **+3 bis +12 Stamina/s** | Regeneriert auch beim Sprinten; Stufe V senkt Sprintkosten um 15 % |
| 🟣 `NEU` | **Nebel & Halluzination** | – | **Statuseffekt `hallucinated`** | Progressive Trugbilder, Schein-Items & Phantom-Spinnen |
| 🟣 `NEU` | **Klettersystem (Wall Climb)** | Nur Rampen | **Kletterranken an Klippen** | Erklimmen von Felswänden via Ranken |
| 🟣 `NEU` | **Schutz-Talisman: Klarglas-Ohrringe** | – | **Perk `clear_sight`** | Immunität gegen Halluzinationen & lichtet den Nebel |
| 🟣 `NEU` | **Esma & Hexenturm** | – | **Voll begehbares Turminneres** | Neue Residentin mit Kessel, Möbeln und Alchemie-Brauen |
| 🟣 `NEU` | **Krähenbaum** | – | **Großer Raben- & Krähenhort** | Zentraler Anlaufpunkt für gefiederte Gefährten |
| 🟢 `FIX` | **Sprint-Skalierung (6.0.1)** | Statische Kosten | **Glutatem V: 0.85x Sprintkosten** | Saubere StaminaComponent-Skalierung bei aktivem Glutatem |

---

### 🔮 Sneak Peek: Was brodelt in V0.7?
*„Mit dem klaren Blick der Klarglas-Ohrringe und den Essenzen aus Esmas Kessel weichen die Lügen des Nebels – doch in den Tiefen unter dem Schiefergestein hallen alte Echos wider. Verlorene Minengänge, uralte Verliese und vergessene Ruinen warten darauf, wiederentdeckt zu werden...“*

---

## [V0.5.0 Beta] – 2026-11-10
### 🦅 Schwingen & Tiefen: Oberflächenschwimmen, der Lichtfischer, Gefiederte Begleiter & die Himmelsriss-Klinge

![Der Lichtfischer der Nacht](docs/img/fisher_poses.png)

*„Die Schatten vor den Toren des Dorfes werden dichter, Wanderer. Während Torben die Klingen im Schmiedefeuer härtet und die Krähen über den Dächern kreisen, regt sich tief unter der Wasseroberfläche etwas Uraltes – angelockt vom kalten Glanz einer trügerischen Laterne...“*

---

### 🌟 Die Großen Highlights

#### 1. 🏊‍♀️ Flüsse & Seen bezwingen: Das neue Schwimmsystem
Tiefes Wasser ist ab sofort keine unüberwindbare Barriere mehr! Ellie kann sich nun frei über die Flüsse und Bergseen der Welt bewegen.

![Nacht an den stillen Bergseen](docs/img/lake_night.png)

* **Ruhiges Brustschwimmen (Standard):** Gleichmäßiger, energiesparender Schwimmstil (34 px/s), um neue Ufer und geheime Buchten abseits der bekannten Furten zu erreichen.
* **Dynamisches Kraulen (Sprint-Schwimmen):** Verbraucht Ausdauer, treibt Ellie dafür aber mit kraftvollen Armzügen (58 px/s) zügig durch starke Wasserströmungen.
* **Kopfsprung & Eintauchen:** Wer im vollen Sprint auf eine tiefe Wasserstelle zurennt, springt mit einem eleganten Kopfsprung direkt kopfüber in die Fluten.
* **Wasser als Zuflucht:** Landgestützte Schattenkreaturen wie Spinnen und Brecher können nicht schwimmen – das tiefe Wasser dient nun als lebensrettender Rückzugsort vor Nahkämpfern.
* 💭 **Developer Insight:** *„Bisher war tiefes Wasser eine unsichtbare Mauer in der Landschaft. Wir wollten, dass die Gewässer lebendig werden und Erkundung belohnen, ohne dass man die ständige Angst vor dem Ertrinken im Nacken hat. Wasser bestraft Unachtsamkeit nicht mit sofortigem Tod, sondern mit taktischer Langsamkeit.“*
* 🔊 **Game Feel:** Speziell abgemischte Audiokulisse mit Eintauch-Plätschern, rhythmischen Schwimmzügen, Auftauchen und dem Abschütteln von Wassertropfen am Ufer.

---

#### 2. 🏮 Schrecken aus der Tiefe: Der Lichtfischer
Nachts ist das Wasser nicht mehr einsam. Mit dem **Lichtfischer** betritt die erste aquatische Schattenkreatur die Welt von Shadowspore.

* **Trügerisches Locklicht:** Im tiefen Wasser treibt nachts eine sanft schaukelnde, bläulich-türkise Laterne an einem langen Stängel. Sie wirkt wie eine harmlose Dorflaterne oder eine leuchtende Wasserpflanze – doch wer neugierig herantritt, weckt das Monster darunter.
* **Tödliche Angriffsmuster:**
  * **Schnapp-Angriff:** Mit weit aufgerissenem Doppelkiefer aus Nadelglas bricht der Fischer hervor, rammt seine Beute und zerrt sie gnadenlos ins kalte Wasser.
  * **Blendlicht:** Die Laterne schwillt an und detoniert in einem blendenden Lichtring, der den Bildschirm in schneeweißes Flackern und falsche Trugbilder hüllt.
  * **Irrlichter:** Entsendet drei zielsuchende Leuchtsporen, die nach einer Flugbahn um das Ziel herum explodieren.
* **Gezielte Schwachstellen:** Die empfindliche Laterne nimmt 1,5x Schaden und bricht vorbereitete Angriffe sofort ab. Nach dem Zuschnappen verharrt das weit geöffnete Maul für einen Gegenangriff (1,6x Bonusschaden).

---

#### 3. 🦅 Gefiederte Gefährten: Das Raben- & Krähen-Bindungssystem
Wilde Krähen und Raben bevölkern nicht länger nur dekorativ die Wiesen und Zäune – ihr könnt nun eine echte persönliche Bindung zu einzelnen Vögeln aufbauen!

![Wilde Krähen und Raben](docs/img/corvids.png)

* **Geduld & Fütterung:** Nähert euch im Schleichen mit passendem Futter in der Hand (Dunkelbeeren, Glutbeeren, Pflanzensamen, Insekten oder gefangenen kleinen Fischen) und bietet es geduldig an.
* **Vom Wildtier zum treuen Gefährten (6 Bindungsstufen):**
  * `Fremd ➔ Beäugt ➔ Bekannt ➔ Vertraut ➔ Freund ➔ Gefährte`
* **Einzigartige Persönlichkeiten:** Jeder Vogel besitzt eigene Charaktereigenschaften (z. B. *Neugierig*, *Scheu*, *Mutig*, *Glitzerliebhaber*, *Nachtschwärmer*), eine individuelle Stimmhöhe und einen eigenen farbigen Fußring.
* **Wertvoller Begleiter:** Ein befreundeter Vogel lässt sich benennen, wird auf der Weltkarte markiert, begleitet euch auf Pfiff, sitzt auf eurer Schulter und bringt glitzernde Geschenke mit. Bei Nacht warnt er euch vor herannahenden Schattenwesen!

---

#### 4. 🗡️ Legendäre Reliktwaffe: Der Himmelsriss (Rissklinge)
Aus einer bezwungenen Boss-Feder von Mornath und reinem Eisen härtet Schmied Torben eine Klinge von unvergleichlicher Zerstörungskraft.

* **Rechtsklick-Doppelhieb (Rissschnitt & Himmelskreuz):** Kein langes Aufladen nötig! Ein schneller Klick entfesselt einen diagonalen Abwärtshieb mit 150 % Schaden und 5 fliegenden Rissfedern. Ein zweiter Klick innerhalb von 0,6 s setzt den Gegenhieb an: 200 % Schaden und ein Fächer aus 7 glühenden Rissfedern (zusammen ein verheerendes X am Ziel).
* **Spitzenriss-Kombo:** Der 3. Stoß der normalen Schwertkombo reißt eine 72 Pixel lange Leerenbahn durch die Luft, die allen Gegnern in der Schneise schweren Flächenschaden zufügt.

---

#### 5. 🪶 Legendärer Talisman: Die Rissfeder
Ein uraltes Relikt des Himmelsspalters Mornath – mit 100 % garantierter persönlicher Beute beim ersten Sieg für jede siegreiche Spielerin im Koop!

![Talisman-Schmuckstücke und Karten](docs/img/talisman_cards.png)

* **Mächtige Passivwerte:** +20 Max-Gesundheit, +3 Rüstung, 30 % schnellere Blinzel-Abklingzeit und 70 % weniger Scheu bei wilden Krähen.
* **Perk: Letzter Flügelschlag:** Schützt vor dem sicheren Tod! Ein tödlicher Treffer wird abgefangen – Ellie verbleibt mit 30 % Gesundheit, erhält 2,5 Sekunden Unverwundbarkeit und schleudert Feinde in einer gewaltigen Federn-Druckwelle zurück (240 s Abklingzeit).
* **Perk: Sturzflug:** Nach jedem Schattensprung trifft der nächste Waffenschlag innerhalb von 3 Sekunden mit gewaltigen **+40 % Bonusschaden**.
* **Federbund-Synergie:** Tragt ihr Klinge und Feder zusammen, verkürzt jeder Treffer des Himmelskreuzes die Abklingzeit des Letzten Flügelschlags um bis zu 32 Sekunden!

---

### ⚖️ Balance & Spielwerte auf einen Blick

| Status | Bereich / Parameter | Vorher | Jetzt (V0.5.0) | Auswirkung im Spiel |
|---|---|---|---|---|
| 🟣 `NEU` | **Wasser-Passierbarkeit** | Unpassierbare Wand | **Voll durchschwimmbar** | Flüsse und Bergseen öffnen neue Erkundungswege |
| 🟣 `NEU` | **Schwimmtempo (Brust / Kraul)** | – | **34 px/s / 58 px/s** | Ausdauerbestimmtes Fortbewegen im Wasser |
| 🟣 `NEU` | **Kopfsprung ins Wasser** | – | **Aktiv aus dem Sprint** | Flüssiger, schneller Übergang von Land in Fluten |
| 🟣 `NEU` | **Nachtmonster: Lichtfischer** | – | **Aktiv in tiefen Gewässern** | Neue Bedrohung bei Nacht mit Schnapp- & Blendangriffen |
| 🟣 `NEU` | **Vogel-Bindungssystem** | Nur scheue Wildvögel | **6 Bindungsstufen (bis Gefährte)** | Zähmen, Füttern, Rufen & Geschenke sammeln |
| 🟣 `NEU` | **Mornath Bossbeute (1. Sieg)** | Regulärer Drop | **100 % persönliche Rissfeder** | Jede Mitspielerin erhält garantiert ihr Bossrelikt |
| 🟢 `BUFF` | **Schattensprung-Cooldown** | Standard | **-30 % Zeit (mit Rissfeder)** | Häufigeres Blinzeln im Gefecht |
| 🟢 `BUFF` | **Angriff nach Blinzeln** | Standard-Schaden | **+40 % Schaden (Sturzflug)** | Belohnt aggressives Vorstoßen aus dem Schatten |
| 🟢 `BUFF` | **Krähen-Vertrauen** | 100 % Fluchtradius | **30 % Fluchtradius (-70 % Scheu)** | Erleichtert Füttern und Zähmen enorm |
| 🟣 `NEU` | **Himmelsriss Grundschaden** | 30 (Leerenklinge) | **40 (Legendäre Himmelsklinge)** | Höchster Grundschaden aller einhändigen Klingen |
| 🟣 `NEU` | **Himmelsriss Doppel-Hieb** | Wuchtschlag | **150 % + 200 % + 12 Projektil-Federn** | Schnelle Schrot-Hiebe für enorme Nahkampfkontrolle |

---

### 🔮 Sneak Peek: Was brodelt in V0.6?
*„Während die Dämmerung über den Flüssen aufzieht, dringt ein herber, süßlicher Geruch aus den Hütten des Dorfes. Kräuter werden gebündelt, alte Tiegel gereinigt und fremdartige Essenzen über offenem Feuer erhitzt... In **V0.6** erwarten euch Alchemie, geheimnisvolle Kessel und seltsame Gebräue der Nacht. Haltet eure Phiolen bereit!“*

---

## [V0.4.0 Beta] – 2026-11-09
### 🌟 Das Große Meilenstein-Update: Lebendiges Hauptmenü, 5-Stufen-Schwertkombo, Schleiergeflecht-Fähigkeiten, Talisman-System mit sichtbarem Schmuck & Kistentruhen

### 🌟 Neuerungen & Verbesserungen

#### 1. Atmosphärisches Hauptmenü & Spiel-Launcher (`src/ui/main_menu*.gd`, `src/world/game_launcher.gd`, `assets/shaders/menu_dark.gdshader`)
* **Lebendiges Hauptmenü:** Ersetzt den bisherigen Direktstart durch ein voll ausgebautes, stimmungsvolles Hauptmenü.
* **Prozedurale Live-Kulisse (`src/ui/menu_world.gd`):** Im Hintergrund läuft eine lebendige Spielwelt mit dynamischem Tag-Nacht-Licht, schwebenden Leere-Sporen und sanft im Wind wiegenden Bäumen.
* **Vollständige Menüführung:**
  * **Neues Spiel:** Startet eine neue Welt mit dem lokalen Helden.
  * **Weiter:** Reibungsloses Fortsetzen vorhandener Spielstände (wird dynamisch ausgeblendet, falls noch kein Spielstand existiert).
  * **Mehrspieler-Lobby:** Hosten eigener Sessions oder Beitreten via IP und Port (`IP:Port`-Eingabefeld mit direkter Tastatureingabe).
  * **Einstellungen:** Konfiguration von Audio-Lautstärken, Tastenbelegung und Anzeigemodi.
  * **Mitwirkende & Beenden.**
* **Modularer GameLauncher (`src/world/game_launcher.gd`):** Saubere Trennung von Argument-Parsing (`--new`, `--join`, `--host`), Szenenwechseln und Netzwerk-Peer-Initialisierung.

#### 2. Kampffähigkeiten, 5-Stufen-Schwertkombo & Finisher (`docs/faehigkeiten_kampf_konzept.md`, `src/components/skill_tree_component.gd`, `data/weapon_classes.json`)
* **Erweiterte Schwertkombo (bis zu 5 Schläge):**
  * **Schlag 1 (Vorhand):** 1,0x Schaden, 120° Bogen, schneller Auftakthieb.
  * **Schlag 2 (Rückhand):** 1,0x Schaden, 120° Bogen.
  * **Schlag 3 (Stoß):** 1,6x Schaden, 40° Bogen, 2,0x Knockback.
  * **Schlag 4 – Aufwärtshieb (`combo_four`):** Freischaltbar ab Stufe 5 im Fähigkeitenbaum. Steiler Hieb von unten nach oben mit 1,25x Schaden, 150° Trefferwinkel und 1,3x Knockback.
  * **Schlag 5 – Wirbelklinge (`combo_five`):** Freischaltbar ab Stufe 15. Verheerender Rundumschlag mit 1,8x Schaden, 330° Trefferbogen, 2,2x Knockback und kraftvollem Bildschirmschütteln.
* **Neue Charakter-Sprites & Bluteffekte:**
  * Spezielles Komboblatt `assets/characters/player_combo.png` (8 Richtungen für alle Kombo-Schritte).
  * Dynamische Blutmaske `assets/characters/player_combo_blood.png` für viszerales Treffer-Feedback.

#### 3. Rework Schleiergeflecht & Fähigkeitenbaum (`src/ui/skill_tree_window.gd`, `src/ui/skill_icons.gd`, `data/skills.json`)
* **Vollbild-Fähigkeitenbaum (Taste K):** Organisch rankendes Astgeflecht für die Disziplinen **KAMPF**, **BEWEGUNG** und **SCHATTEN**.
* **Eigene Pixel-Art-Icons (`tools/art_skill_icons.py`, `docs/img/skill_icons.png`):**
  * Dedizierte 16x16 / 32x32 handgepixelte Glyphen und Icons mit Kantenbloom und Zweigfarben (`#e6c468` Kampf-Gold, `#78f4e6` Bewegungs-Cyan, `#b06bff` Schatten-Violett).
* **Neue Bewegungsskillung „Schleichen“ (`sneak`):**
  * Ermöglicht leises Pirschen; reduziert den Sicht- und Hörradius der Schattenkreaturen drastisch.
* **Skillpunkte-Berechnung:** Exakt `Fähigkeitspunkte = Spielerstufe - 1 - ausgegebene Punkte`.
* **Audio-Feedback:** Neuer atmosphärischer Lernsound beim Aktivieren von Fähigkeiten (`assets/audio/skills/learn.wav`).

#### 4. Talisman-System & Amorphe Schmuckstücke (`docs/talisman_konzept.md`, `src/components/talisman_component.gd`, `src/systems/talisman_rules.gd`, `data/talismans.json`)
* **3 Schmuckgattungen & Domänen:**
  * **Kette (`necklace` / Domäne KÖRPER):** z. B. `silver_chain` (+12 Max-HP, +2 Rüstung).
  * **Armband (`bracelet` / Domäne ANGRIFF):** z. B. `wuchtreif` (+8 % Gesamtschaden, +15 % Wuchtschlag-Schaden, +25 % Lade-Tempo).
  * **Ohrringe (`earrings` / Domäne LEERE):** z. B. `schweigtropfen` (-50 % Alarmradius für Monster, schluckt 25 % allen Schadens).
* **Plätze nach Stufen-Fortschritt:**
  * Vor Stufe 5 versiegelt.
  * Slot 1 ab Stufe 5 freigeschaltet.
  * Slot 2 ab Stufe 15 freigeschaltet.
  * Slot 3 ab Stufe 25 freigeschaltet.
* **Regeln & Begrenzungen:** Maximal ein Schmuckstück jeder Gattung anlegbar; intelligentes Tauschen per Rechtsklick oder Drag & Drop; sofortige Werteverrechnung ohne illegale Selbstheilungs-Exploits.

#### 5. Sichtbarer Schmuck auf dem Heldenkörper (`src/fx/talisman_art.gd`, `src/fx/talisman_layer.gd`, `tools/art_hero_jewelry.py`)
* **Visuelle Schmuckdarstellung:** Angelegte Talismane werden pixelgenau und richtungsabhängig auf dem Sprite des Spielers gerendert (Silberkette um den Hals, Goldreif am Schwertarm, schwebende Leeretropfen an den Ohren).
* **Reaktive Effekte:** Geschluckter Schaden bringt die Ohrringe durch Lichtimpulse zum Leuchten (`absorb`).
* **Sound-Design (`assets/audio/talisman/`):** Eigene Sounds für das Anlegen von Gold-, Silber- und Leerenstahl-Schmuck (`equip_gold.wav`, `equip_silver.wav`, `equip_voidsteel.wav`, `absorb.wav`, `off.wav`).

#### 6. Kisten-, Truhen- & Lagersystem (`src/systems/item_box.gd`, `src/ui/box_window.gd`, `src/town/town_manager.gd`)
* **Modulares Lagerbox-System (`ItemBox`):** Platzierbare Truhen in der Welt und im Dorf mit frei konfigurierbarer Slotgröße.
* **Truhen-UI (`BoxWindow`):**
  * Schneller Itemtransfer per Shift-Klick zwischen Rucksack und Truhe.
  * Sortierfunktion und Schnell-Stapeln (`Quick Stack`) gleicher Gegenstände.
  * Volle Synchronisation im Host-Authoritativen Mehrspielermodus.

---

### ⚖️ Veränderungen & Parameter (Vorher &rarr; Nachher)

| Bereich / Parameter | Vorher (`V0.3.2`) | Jetzt (`V0.4.0`) | Bedeutung |
|---|---|---|---|
| **Schwertkombo-Schlagzahl** | 3 Schläge (fest) | **Bis zu 5 Schläge** | Durch Upgrades Aufwärtshieb (`combo_four`) und Wirbelklinge (`combo_five`) |
| **Maximaler Kombo-Einzelschaden** | 1,6x (3. Schlag / Stoß) | **1,8x (5. Schlag / Wirbelklinge)** | Enormer Finisher-Schaden gegen Horden |
| **Kombo-Trefferwinkel Finisher** | 40° (Stoß) | **330° (Wirbelklinge)** | Trifft nahezu die gesamte Umgebung im Nahkampf |
| **Wuchtschlag-Aufladezeit (mit Wuchtreif)** | 1,00 s (Standard) | **0,80 s (-20 % Zeit / +25 % Tempo)** | Deutlich schnellere Einsatzbereitschaft des Wuchtschlags |
| **Wuchtschlag-Schaden (mit Wuchtreif)** | 3,40x Basis | **3,91x (3,40 * 1,15)** | +15 % Bonus-Schaden auf voll geladene Wuchtschläge |
| **Allgemeiner Waffenschaden (mit Wuchtreif)** | 1,00x | **1,08x (+8 %)** | Dauerhafter Bonus auf alle regulären Angriffe |
| **Max-HP Bonus (mit Silberkette)** | 0 | **+12 Max-Gesundheit** | Höherer Lebenspool (ohne Gratis-Heilung beim Anlegen) |
| **Rüstungs-Bonus (mit Silberkette)** | 0 | **+2 Rüstung** | Reduziert erlittenen physischen Schaden |
| **Erlittener Schaden (mit Schweigtropfen)** | 100 % (Standard) | **75 % (25 % geschluckt)** | Schützt auch vor Schaden über Zeit (DoT) |
| **Monster-Wahrnehmung (mit Schweigtropfen)** | 100 % Radius | **50 % Radius (-50 % Alarm)** | Schattenspinnen, Lauscher & Brecher bemerken den Helden erst auf halbe Distanz |
| **Talisman-Plätze Stufe 1–4** | Keine | **0 (versiegelt)** | Plätze müssen durch Stufenaufstiege verdient werden |
| **Talisman-Plätze Stufe 5 / 15 / 25** | Keine | **1 / 2 / 3 Plätze** | Erweitert die tragbaren Schmuckstücke mit dem Spielfortschritt |
| **Spielstart** | Direktstart in die Welt | **Hauptmenü mit Live-Hintergrundwelt** | Volle Menünavigation für Solo, Host, Join & Optionen |
| **Truhen & Kisten** | Nur statisches Dorflager | **Modulare Truhen mit Shift-Klick & Sortierung** | Bequemes Einlagern und Sortieren von Beute |

---

## [V0.3.2 Beta] – 2026-11-09
### 🗺️ Boss-Kartenmarker, Mornath-Replay-Fix & Menü-Polishing

### 🌟 Neuerungen & Verbesserungen

#### 1. Mornath-Hologramm Boss-Kartenmarker (`data/map_markers.json`, `src/ui/map_window.gd`)
* **Neuer Weltkarten-Marker für den Bosskampf:** Sobald das Hologramm nach dem ersten Sieg aktiv ist, erscheint ein markantes Symbol auf der Weltkarte (`kind: "boss"`, Farbe `#6fe8ff`).
* **Visuelle Karteneffekte:** Glitch-Ring, pulsierendes Emblem und informativer Tooltip (`MORNATH - DER HIMMELSSPALTER`, Entfernungsanzeige und Status `ERNEUTER KAMPF BEREIT`).
* **Saubere Einblendung:** Der Marker wird nur angezeigt, wenn das Hologramm vollständig sichtbar ist (`_appear == 1.0`), um Ghosting während Phasenübergängen zu vermeiden.

#### 2. Boss-Replay & Arena-Instandsetzung (`src/entities/enemies/sky_cleaver.gd`, `src/world/world_level.gd`)
* **Sauberer Replay-Start:** Nach Besiegen des Bosses wird das `defeated`-Signal gesendet, wodurch die gespeicherte Checkpoint-Phase in `WorldLevel._arena_phase` gelöscht wird. Ein erneutes Rufen startet nun garantiert bei **Phase 1 mit 100 % HP**.
* **Arena-Reparatur:** Beim Start eines erneuten Kampfes werden alle Arenasäulen automatisch regeneriert (zerstörte Säulen wieder aufgebaut, Flammen gelöscht: `broken = false`, `fury = 0.0`).

#### 3. Menü- & UI-Polishing (`src/ui/pause_menu.gd`)
* Aufgeräumte und harmonisierte Entwickler-Menüführung für Story-Sprünge, Boss-Teleports und Replay-Tests.

---

### ⚖️ Veränderungen & Bugfixes (Vorher &rarr; Nachher)

| Bereich / Parameter | Vorher (`V0.3.1`) | Jetzt (`V0.3.2`) | Bedeutung |
|---|---|---|---|
| **Mornath Replay-Startphase** | Checkpoint blieb erhalten (z. B. Start in P2/P3) | **Immer Phase 1 (Startphase 0, 100 % HP)** | Bosskampf ist nach Sieg voll replaybar |
| **Arena-Säulen im Replay** | Blieben zerstört oder brennend | **Vollständig regeneriert und erloschen** | Saubere Kampfarena bei jedem neuen Start |
| **Mornath-Hologramm auf Weltkarte** | Kein Marker vorhanden | **Cyan/Magenta Boss-Marker (`kind: "boss"`)** | Spieler finden die Replay-Arena sofort |
| **Marker-Sichtbarkeit** | Sofortige Einblendung | **Erst bei voller Deckkraft (`_appear == 1.0`)** | Kein Flackern während Übergängen |

---

## [V0.3.1 Beta] – 2026-11-09
### 🗡️ Schwerer Angriff (Wuchtschlag), Level-Fortschrittsfenster & Nacht-Director Rework

### 🌟 Neuerungen

#### 1. Schwerer Angriff: Wuchtschlag (`docs/heavy_attack.md`, `src/systems/heavy_rules.gd`)
* **Sekundärangriff (Rechtsklick / L2):** Aufladbarer, wuchtiger Schlag für Einhandschwerter.
  * **Stufe 1 (ab 0,35 s):** Breiter Weithieb (150° Bogen, 2,2x Schaden, 2,0x Knockback, 230 px Vorwärtsdrang).
  * **Stufe 2 (Voll aufgeladen nach 1,0 s):** Maximaler Schmetterhieb (3,4x Schaden, 3,0x Knockback, 300 px Vorwärtsdrang, Erschütterungs-Screenshake).
* **Visuelle Effekte & Klingenbänder:** Leuchtende Klingenstreifen (`_draw_heavy_ribbon`), Funkenfokus an der Klingenspitze (`_charge_glint`) und Staubexplosion beim Bodenaufprall (`_impact_dust`).
* **Neue Charakter-Assets (`assets/characters/`):** Eigenes Animationssheet `player_heavy.png` (8 Himmelsrichtungen, Ausholen, Zittern bei voller Ladung, Niederschlag) sowie Blutspritzer-Maske `player_heavy_blood.png`.
* **Sound-Design (`assets/audio/heavy/`):** 7 neue Sounds für Klingenheben (`draw`), Loslassen (`swing`), Treffer (`hit`), Bodenaufschlag (`thud`), Abbrechen (`drop`), Ladebereitschaft (`ready`) und volle Aufladung (`full`).

#### 2. Level-Fortschrittsfenster & Belohnungen (`docs/level_fortschritt_konzept.md`, `src/ui/progress_window.gd`)
* **Neues Vollbild-Fortschritts-UI (Taste P / Pausemenü „FORTSCHRITT“):**
  * Eigene Fortschrittsrebe über 4 Epochen: Dämmerung (1–5), Erstes Licht (6–10), Blüte (11–20) und Tiefe (21–30).
  * Blütenknoten (`BloomOrb`): Pixel-Blüten mit Blütenblättern und Staubfäden, die sich beim Halten von E oder Mausklick (`hold to claim`) langsam entfalten.
  * Belohnungen je Level: Erhöhung von Max-Gesundheit und Stamina.
  * Meilensteine alle 5 Stufen: Rüstungspunkte (+1/+2), Überheilung und Freischaltung zusätzlicher Talisman-Plätze im Inventar.
* **Audio-Feedback (`assets/audio/progress/`):** Sounds für Abholen (`claim`), Fokus (`focus`), Meilenstein (`milestone`), Öffnen (`open`) und Bereitschaft (`ready`).

#### 3. Nacht-Director Rework & Monster-Verhalten (`docs/nacht_monster_konzept.md`, `src/world/night_director.gd`)
* **Dynamische Nachtphasen & Beats (`data/night.json`):** 6 taktische Phasen (Kundschafter `scouts` → Aufbaustufe `build` → Atempause `lull` → Sammelruf `call` → Höhepunkt `peak` → Letzter Ansturm `last_rush`).
* **4 Nachtstufen:**
  * `tasten` (ab Tag 0): Einzelne Schattenspinnen.
  * `lauschen` (ab Tag 3): Spinnen + Lauscher, koordinierte Überfälle.
  * `druck` (ab Tag 7): Alle Monsterarten inkl. Brecher, Gedächtnissystem aktiv.
  * `flut` (ab Tag 12): Große Horden, Elite-Monster möglich.
* **Mondphasen-Einfluss:** Neumond erhöht Spawn-Budget um +30 % und dichtet Nebel an; Vollmond senkt Spawns um 15 %.
* **Geräusche & Spuren (`evidence`):** Laufen, Schwertschläge und Bauen erzeugen Lautstärke, die Monster anlockt.
* **Letzter Ansturm (`last_rush`):** Bei 80 % Nachtverlauf fordert das Spiel zum Durchhalten bis zum Sonnenaufgang auf („HALTE BIS ZUR DÄMMERUNG“).

#### 4. Mornath-Arena-Story & Hologramm (`docs/boss_arena.md`, `src/world/arena_story.gd`)
* Neuer Vorbereitungsbereich vor der Boss-Arena mit gefallenen Rittern (`arena_knight.gd`).
* Interaktive Inspektions- und Hologramm-Szenen (`mornath_hologram.gd`, Shader `mornath_hologram.gdshader`) zur atmosphärischen Einstimmung auf den Kampf.

---

### ⚖️ Veränderungen & Vorher-Nachher-Werte

| Parameter / Bereich | Vorher (`V0.3.0`) | Jetzt (`V0.3.1`) | Bedeutung |
|---|---|---|---|
| **Level-XP Basiswert (`levels.base`)** | 30 | **22** | Frühere Level erfordern weniger XP (schnellere Belohnung) |
| **Level-XP Exponent (`levels.exponent`)** | 1,70 | **1,45** | Flachere XP-Kurve für flüssigeren Stufenaufstieg |
| **Schwerer Angriff Schaden** | – | **2,2x (min) bis 3,4x (voll)** | Enorme Durchschlagskraft bei voller Aufladung |
| **Schwerer Angriff Reichweite** | 1,0x (Basis) | **1,25x (+25 %)** | Größere Trefferfläche |
| **Schwerer Angriff Schwungwinkel** | ~100° | **150°** | Breiter Rundumschlag |
| **Schwerer Angriff Vorstoß (`lunge`)** | 0 | **230 bis 300 px** | Spieler gleitet im Hieb dynamisch nach vorn |
| **Nacht-Wellen-Struktur** | 3 starre Wellen | **5 Phasenfreigaben + 6 Nacht-Beats** | Lebendigerer, dynamischer Nachtablauf |
| **Nacht-Spawns Neumond** | 1,0 (Standard) | **1,30 (+30 % Spawns)** | Deutlich gefährlichere Nächte bei Neumond |
| **Nacht-Spawns Vollmond** | 1,0 (Standard) | **0,85 (-15 % Spawns)** | Ruhigere Nächte bei hellem Mondlicht |
| **Monster-Elite HP** | Standard | **1,45x (+45 % Leben)** | Robuste Mini-Bosse in späteren Nächten |

---

## [V0.3.0 Beta] – 2026-11-09
### 🔨 Der Schmied Torben, die Schmiede, Eisenerz & Waffen-Verfeinerung

### 🌟 Neuerungen

#### 1. Der Schmied Torben & die Dorfschmiede
* **Neuer NPC Torben (`docs/torben_konzept.md`, `data/torben_rig.json`):**
  * Schweigsamer Schmied mit eigener Persönlichkeit („HM.“, „HÄLT.“, „RISKANT.“, „SCHROTT.“).
  * Vollständiges Charakter-Spritesheet (`assets/characters/torben.png`) mit Hammer-, Esse- und Amboss-Animationen sowie Glow-Layer für glühendes Eisen (`torben_glow.png`).
* **Neues Dorfgebäude „Schmiede“ (`data/town.json`, `tools/art_smithy.py`):**
  * Maße: 152 × 140 px Frame, 112 × 38 px Kollisionsbasis.
  * Baukosten: 16 Holz, 30 Stein, 6 Bretter, 8 Eisenerz (Bauzeit: 40 s, Siedlungswert: 18).
  * Animierte Esse mit Partikeln (Rauch am Schornstein, Funkenflug am Amboss `#ffb25a`), dynamisches Feuerlicht (Radius 78, Energie 1.15, Flimmern 0.4).
  * Windbewegte Deko: Laternen (links/rechts mit Glow), Schmiedeschild und Wimpel.
  * 6 Abnutzungs- und Alterungsstufen (Wear A/B/C, Moos A/B, Vernachlässigung).
  * Schmiede-Shop (`data/shops.json`): Tabs für Fertigen, Bestellen, Kaufen, Verkaufen und Verfeinern.

#### 2. Eisenerz & Metallurgie
* **Eisenerzfelsen in der Spielwelt (`data/plants.json`, `assets/props/iron_rock*`):**
  * 6 visuelle Varianten blauvioletten Gesteins mit rotbraunen Erzadern und subtilem Glow.
  * Abbau per Spitzhacke: 3 bis 6 Schläge; droppt Eisenerz (`iron_ore`) und Stein (Regenerationszeit: 3 Tage).
* **Neue Materialien (`data/items.json`):**
  * `iron_ore` (Eisenerz): Rohes Erzgestein für die Esse.
  * `iron_ingot` (Eisenbarren): Aus Erz geschmolzen und in Form gegossen.
  * `iron_plate` (Eisenplatte): Flach geschlagene, genietete Platten für Riegel und Beschläge.
* **Neue Schmiede-Rezepte (`data/recipes.json`):**
  * Eisenbarren: 2 Eisenerz + 1 Holz (Schmelzen an der Esse).
  * Eisenplatten: 3 Eisenbarren → 2 Platten (Torben fertigt sie als Auftrag in 60 s).

#### 3. Waffen-Verfeinerungssystem (`RefineRules`, `data/refine.json`)
* **Stufen +1 bis +15:**
  * **Stufe 1 (Anschmieden, +1 bis +5):** 100 % Erfolgsgarantie. Kostet Eisenbarren & Kupfer.
  * **Stufe 2 (Härten, +6 bis +10):** Freigeschaltet ab 20 Vertrauen. Erfolgschance sinkt von 85 % auf 50,8 %. Pity-System (+3 % pro Fehlschlag, max. 15 %) und 50 % Material-Erstattung bei Fehlschlag.
  * **Stufe 3 (Leerenschmieden, +11 bis +15):** Freigeschaltet ab 50 Vertrauen. Chance sinkt von 42,2 % auf 8 % bei +15. Benötigt Leersplitter, Schattenkerne und Leerenschlacke.
* **Waffen-Meilensteine:**
  * **+5 („Gehärtet“):** +1 Waffenreichweite.
  * **+10 („Leerenfest“):** +1 Reichweite, gelegentliche Lichtfunken entlang der Klinge (`_edge_glints`).
  * **+15 („Vollendet“):** +1 Reichweite, +5 % Angriffsgeschwindigkeit, durchgehender goldener Klingenpuls (`_draw_edge_glow`).
* **Interaktive Veredelungs-UI (`refine_reveal.gd`):**
  * Enthüllungs-Animation mit Sound-Feedback (`ember.wav`, `success.wav`, `perfect.wav`, `fail.wav`).

#### 4. Blattkriecher-Ökosystem (`LeafCritters`, `data/leaf_critters.json`)
* Kleintiersimulation auf Büschen, Gräsern und Uferpflanzen.
* 3 Arten mit individuellem Verhalten:
  * **Käfer (`beetle`):** 26 s Rast, 3,2 s Krabbeln (4 px Schritt), nur tagsüber aktiv.
  * **Raupe (`caterpillar`):** 31 s Rast, 4,8 s Krabbeln (3 px Schritt).
  * **Schnecke (`snail`):** 34 s Rast, 9,0 s Kriechen (3 px Schritt), auch nachts aktiv (Nachtlimit 0,75, Feuchtgebiets-Fokus 58 %).
* Fluchtverhalten bei Berührung oder Fällen der Pflanze (`departure_seconds: 1.4 s`).

---

### ⚖️ Veränderungen & Vorher-Nachher-Werte

| Parameter / Bereich | Vorher (`V0.2.4`) | Jetzt (`V0.3.0`) | Bedeutung |
|---|---|---|---|
| **Schmiede-Station für `sword_iron`** | Werkstatt (Gustav) | **Schmiede (Torben)** | Gustav fertigt Holz, Torben Metall |
| **Materialien `sword_iron`** | 1 Schwert, 2 Bretter, 4 Steine, 2 Splitter | **1 Schwert, 2 Eisenplatten, 2 Barren, 1 Splitter** | Echte Eisenverarbeitung |
| **Arbeitsaufwand `sword_iron`** | 100,0 s | **120,0 s** | Anspruchsvollerer Schmiedeprozess |
| **Schmiede-Station für `sword_basic`** | – | **Schmiede (2 Barren + 1 Brett)** | Grundschwert direkt in Schmiede herstellbar |
| **Critter-Spawn Busch (`bush`)** | 0,20 (20 %) | **0,12 (12 %)** | Weniger überfüllte Sträucher |
| **Critter-Spawn Beerenbusch** | 0,20 (20 %) | **0,12 (12 %)** | Ausgewogenere Fauna |
| **Critter-Spawn Gras (`grass`)** | 0,20 (20 %) | **0,10 (10 %)** | Reduzierte Insektendichte auf Wiesen |
| **Critter-Spawn Uferblume** | 0,20 (20 %) | **0,12 (Snail-Bias 1,35)** | Schnecken bevorzugen Feuchtpflanzen |
| **Critter-Spawn Rohrkolben** | 0,20 (20 %) | **0,14 (Snail-Bias 1,40)** | Höchste Schneckenpräferenz am Wasser |
| **Waffen-Skalierung (`attack_component`)** | Feste Basiswerte | **`Items.stat(stack, ...)`** | +5 % Schaden pro Veredelungsstufe |

---

## [V0.2.4 Beta] – 2026-11-09
### ☀️ Tageslicht-Art-Pass, Schloss-Flur & Saal, Intro-Sequenz

### 🌟 Neuerungen
* **Tageslicht-Beleuchtungsfeld (`DaylightField`, `daylight.gdshaderinc`):** 128×96 R8-Baumkronenmaske synchronisiert Licht & Schatten über Boden, Flora, Wasser und Figuren. Weltverankerte Wolkenschatten und 4 stimmungsvolle Lichtschäfte (`day_shafts.gdshader`).
* **Schloss-Erweiterung (`data/interiors.json`):** Großer Flur (`flur_lang`, 1856 px), Verbindungsgang (`flur_gang`), Eingangshalle (`flur_saal`, 704 × 776 px) und 6 Dienerzimmer. Interaktive Ruhebänke (`HallSeat`).
* **Raum-Schleier (`room_veil.gdshader`):** Unbetretene Räume sind in Nebel gehüllt, der sich beim Eintreten hebt.
* **Intro-Sequenz (`room_intro.gd`):** Erwachen im Kleiderschrank mit Audio-Cues und animierter Intro-Krähe am Fenster.

### ⚖️ Veränderungen
* **Personalraum-Größe:** Von 304 × 252 px verkleinert auf `256 × 212 px` (kompakter, stimmiger).
* **Türmechanik Personalraum:** `door_locked: true` → `needs: broom_taken` (Besen muss genommen werden).
* **Pollenpartikel (`DayMotes`):** Von 70 Partikeln (2×2 px) auf 38 dezent beleuchtete 1-px-Pollen reduziert.
* **Goldstunden-Stärke:** Von 0 auf `0.85` korrigiert (Mittagsschwelle schneidet Goldlicht nicht mehr ab).

---

## [V0.2.3 Beta] – 2026-11-09
### 🔥 Bosskampf Phase 3 („Der Himmel brennt“), Gustav-Questline, Status-Effekte

### 🌟 Neuerungen
* **Mornath Boss Phase 3:** Verwandlung bei 10 % HP, pinkes Höllenfeuer (`fire_arena.gd`), Sturzflug-Angriff (`dive`, 36 Dmg, 400 px/s), Glutbälle und Brandmale.
* **Gustav-Questline:** 8-teilige Rettungskette (`gustav_rescue`) mit Schattenspinnen-Kampf, Wagen-Befreiung und Dämmerungs-Eskorte.
* **Status-Effekt-System (`StatusEffects`):** Modulares Brennen (`burn`, 2 % Max-HP DoT), Status-Tags über Einheiten und schadensspezifische DoT-Zahlen ohne Flinch-Unterbrechung.
* **Health-Erweiterungen:** `take_survivable()` (Story-Treffer lassen min. 1 HP übrig), `god_mode` Dev-Cheat.

### ⚖️ Veränderungen
* **Boss-Phasen:** 2 Phasen → **3 Phasen (P3 startet bei <= 0.1 HP)**.
* **Angriffspause P3 (`gap`):** 0,55 s – 0,95 s (starker Angriffsdruck, P2 war 0,9 – 1,5 s).
* **Boss-Regenwellen P3:** 3 Wellen → **7 Wellen** (Schaden von 24 auf 28 erhöht).
* **Urteil-Säulen-HP P3:** 240 HP → **420 HP** (Zeitlimit von 28 s auf 22 s verkürzt).
* **Gustav-Ankunft:** `needs: workshop` → **`needs: gustav_joined`** (erst nach aktiver Rettung).

---

## [V0.2.2 Beta] – 2026-11-09
### 🏛️ Boss Arena Overhaul, Personalraum-Interior, Kampf-Balancing

### 🌟 Neuerungen
* **Personalraum:** Erstes vollständiges Zimmer-Interior mit Bett, Nachttisch, Besen, Schrank und Innenraum-Krähe.
* **Arena-Grafik:** Bodenmasken, Glow-Decals und 26+ dekorative Props (Feuerschalen, Kristalle, Banner, Schutt).
* **Profiling-Tools:** `profile_chunks` und `profile_gen` zur Messung der Generierungszeiten.

### ⚖️ Veränderungen
* **Boss-Angriffsfenster P1 (`gap`):** Von [0.5, 1.0] s auf **[1.3, 2.1] s** vergrößert für bessere Lesbarkeit.
* **Boss-Angriffsschaden:** Shot (18 → 27), Rain (16 → 24), Line (17 → 26), Chase (22 → 32).
* **Telegraph-Warnungen:** Rain-Warnzeit von 0,95 s auf **1,2 s**, Chase-Warnung von 0,7 s auf **0,95 s** verlängert.
