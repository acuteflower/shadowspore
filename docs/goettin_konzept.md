# Die Göttin der Wegsteine & Der Sternensaal (Konzept)

> **Status: Gebaut & auf v2-Interstellar-Raum erweitert (siehe `docs/caelia_interstellar_konzept.md`, `GoddessSystem`, `StarHallRoom`).** Dieses Dokument hält das abgestimmte Design für die Göttin (Gegenspiel zur Leere), ihren schwebenden Sternensaal, die erste Rettungs-Introduction, den Statuen-Zugang, die Läuterung von `SCHATTENSCHRITT` → `LICHTSCHRITT` und das Gerüst für spätere Gaben fest.

---

## 1. Kernidee & Einbindung in die Welt

In Shadowspore stehen überall im Land alte Statuen einer verschleierten Jungfrau – die Wegsteine der **„Wächterin“** ([waystones.md](waystones.md), [raetsel_konzept.md](raetsel_konzept.md)). Bisher waren sie stille Monumente und Reiseanker. Dieses System macht ihr Urbild zu einer echten, begehbaren Figur mit eigenem kosmischem Sanktuar:

* **Das Gegenspiel zur Leere:**
  * Die **Leere** ist das hungrige Nichts zwischen den Sternen – sie löscht Licht, verzerrt Erinnerungen und korrumpiert Wesen zu fast schwarzen Körpern mit violetten Adern und magentafarbenen Augen.
  * Die **Göttin** ist ihr Gegenpol: Bewahrerin von Form, Erinnerung, Sternenlicht und Schutz.
* **Warum sie nicht einfach alles selbst heilt:** Durch den Einbruch der Leere wurde ihre Verbindung zur Welt gebrochen; ihre Statuen draußen sind überwuchert und mit dunklen Kristallen versiegelt. Sie kann die Welt nicht mehr unmittelbar betreten – **erst jede erwachte Statue gibt ihr einen Anker und ein Stück Präsenz zurück**.
* **Die Fantasie für die Spielerin:** Wer draußen eine Statue erweckt hat, knüpft unbewusst ein Band zu ihr. In Ellies größtem Sturz (ihrem ersten tödlichen Fall danach) reißt die Göttin sie aus dem Zugriff der Leere zu sich hinauf in den Sternensaal – und wandelt ab dort nicht nur ihre Fähigkeiten vom Schatten ins Licht, sondern wird zur dauerhaften Zuflucht über jede Statue.

---

## 2. Die Göttin (Charakter, Name & Auftritt)

### 2.1 Identität & Name
* **Erste Begegnung:** Zu Beginn trägt sie – wie ihre Statuen – nur den Titel **`DIE WÄCHTERIN`** (`DialogueBox`-Mechanik analog zu `known_flag` / `known_name`).
* **Enthüllung:** Im ersten langen Gespräch vor dem Thron nennt sie Ellie ihren wahren Namen (Platzhalter/Vorschläge für den Dialogautor: **CAELIA**, **SOLENA** oder **AELIA**).
* **Wesen & Tonfall:** Ruhig, warm, uralt-würdevoll, niemals hektisch oder allmächtig-abgehoben. Man spürt, dass auch sie vom Kampf gegen die Leere gezeichnet ist und Ellie nicht als bloßes Werkzeug sieht, sondern als jemanden, den sie durch die erwachten Statuen schon beobachtet hat.

### 2.2 Visuelle Gestaltung (gemäß [design_guide.md](design_guide.md))
Sie ist das **lebendige Vorbild** der Wegstein-Statuen aus [art_waystone.py](tools/art_waystone.py):
* **Größenmaßstab:** Ca. **1,6× so hoch wie Ellie** (ca. 65–70 px Gesamthöhe stehend gedacht; auf dem Thron sitzend wirkt sie dadurch majestätisch und übermenschlich, aber nahbar).
* **Silhouetten- & Farbmerkmale:**
  * Blasse Sternenlicht-Haut, langes fließendes **silber-lichtgoldenes Haar** (`#e9e3f7` / `#fffaf0` mit sanftem Goldschimmer).
  * Gewand in tiefem Nachtblau/Elfenbein mit fein gezeichneten **türkisen (`#78f4e6`) und goldenen (`#e6c468`) Adern/Säumen** – die bewusste Umkehrung der schwarz-violetten Leeren-Adern.
  * Ein goldener **Heiligenschein mit schwebenden, facettierten Lichtkristallen** hinter dem Haupt (als eigene `Unlit`-Leuchtschicht, pulsiert ruhig und reagiert beim Sprechen/Segnen).
  * Leuchtende, ruhige Augen (`#d0fff8`) und ein feiner, leicht bewegter Sternenstaub-Schleier.
* **Thron-Animationen:** Ruhige Sitz-Idle (Atmen, sanft wehendes Haar/Schleier, schwebender Kristallfunke über einer Hand), Zuwenden/Neigen beim Gespräch, feierliche Segens-Geste (beide Hände heben sich leicht, Kristallkranz flammt golden auf).
* **Dialog-Portrait:** Eigenes Bust-Portrait (`103×153` logisch, `206×306` Anzeige) nach dem verbindlichen Vertrag in [dialogue_art.md](dialogue_art.md), inkl. Zwinkern und unbekannter Silhouette vor der Einführung.

---

## 3. Die neue Umgebung: Der Sternensaal

Ein **leuchtender, göttlicher Saal mitten im Universum** – völlig offen, ohne Wände und Decke, schwebend in der endlosen Leere der Sterne.

### 3.1 Atmosphäre & Kosmos
* **Keine Wände, kein Dach:** Jenseits der niedrigen Marmor-Kanten und gebrochenen Balustraden öffnet sich direkt der tiefe Kosmos:
  * Tiefschwarzes All (`#040208` / `#09060f`) mit **mehreren Parallax-Ebenen scharfer Pixel-Sterne**, blassen türkis-goldenen Sternennebeln und schwebenden Marmor-/Kristalltrümmern in der Tiefe.
  * Am äußersten Horizont zeichnen sich subtil **dunkle Risse der Leere** ab – eine stille visuelle Erinnerung an das Ringen zwischen ihr und der Leere.
* **Boden & Licht:**
  * Heller, polierter Violett-Marmor mit eingelassenen goldenen Sternlinien und **türkis glühenden Leylines** (`Unlit`), angelehnt an den gereinigten Boden der Wegsteine (`art_waystone_ground.py`).
  * Keine `DayNight`-Abdunklung: Der Saal hat seine eigene konstante, kristallklare Sternenbeleuchtung, schwebende gold-türkise Lichtmotten und leise glockenartige Sphärenklänge.

### 3.2 Räumlicher Aufbau (von Süd nach Nord)
1. **Ankunftskreis (Süden):**
   * Ein runder Plattform-Vorbau mit dem Wegstein-Runenring. Hier erscheint Ellie aus einer weichen Lichtsäule.
   * Direkt am Rand steht der Rückkehr-Anker (**`E ZURÜCKKEHREN`**).
2. **Die offene Sternenbrücke (Mitte):**
   * Ein breiter, schwebender Marmorgang zwischen Ankunftskreis und Thron.
   * Flankiert von freistehenden Kristall-Pfeilern, schwebenden Steinfragmenten und **flachen Spiegelbecken** im Boden, in denen der Sternenhimmel unter Ellies Schritten reflektiert (verwandt mit der Bildsprache von `StarMirror`).
   * **Lebendige Welt-Kopplung:** Mit jeder in der Welt erwachten Wegstein-Statue entzündet sich ein weiteres Lichtpaar/Pfeilerelement entlang der Brücke – der Saal wächst mit Ellies Fortschritt mit.
3. **Das Thron-Podest (Norden):**
   * Über wenige breite, niedrige Stufen leicht erhöht.
   * Ein monumentaler, filigraner **Thron** aus Mondstein-Marmor und Goldstreben, dahinter ein großer, langsam rotierender **Sonnen- & Sternenkristall-Kranz**.
   * Rund um das Podest stehen **drei unaufdringliche Steinsockel/Nischen** als vorbereiteter Raum für spätere Gaben-Altäre oder Reliquien.

### 3.3 Technische Einordnung
* Nutzt das bestehende Pocket-Space-Prinzip von `Interiors` (fester Slot weit außerhalb der `1100×1100`-Welt, gleiche Koordinaten auf allen Peers), ersetzt dort jedoch die dunkle Schattenwand (`interior_dark.gdshader`) durch einen eigenen **Kosmos-Parallax-Hintergrund** und freie Plattform-Kollisionen entlang der schwebenden Kanten.

---

## 4. Die erste Introduction (Rettung vor dem Tod)

Die Göttin wird nicht beiläufig über ein Menü gefunden, sondern durch ein einmaliges, dramatisches Schlüsselereignis eingeführt:

* **Voraussetzung (Host-geprüft):**
  1. Das Intro/Opening ist abgeschlossen (`opening_over == true`).
  2. In der Welt wurde **mindestens eine Wegstein-Statue erweckt** (`Waystones.awake_count() >= 1`).
  3. Dieser Spieler wurde noch nicht von der Göttin eingeführt (`!goddess_introduced`).
* **Trigger:** Der **erste tödliche Treffer**, der diesen Spieler eigentlich töten würde (technisch sauber über den bestehenden `ward`-Haken in `HealthComponent._warded` abfangbar!).
* **Ablauf der Sequenz:**
  1. **Abfangen des Todes:** Im Moment des tödlichen Treffers friert das Spielgefühl kurz ein (Slow-Motion / Zeitlupe wie beim Hinterhalt), statt der dunklen Todesszene reißt eine **türkis-goldene Lichtsäule** über Ellie auf und stößt umliegende Schatten visuell zurück.
  2. **Übergang ins All:** Ein weiß-türkises Lichtblendwerk löst in tiefe Stille und Sternenfunken auf.
  3. **Ankunft im Sternensaal:** Ellie steht geheilt am Ankunftskreis im Süden – am anderen Ende des langen, offenen Sternengangs strahlt der Thron.
  4. **Selbst hingehen:** Die Kontrolle kehrt sanft zurück (kein langer Zwangs-Autopilot über den ganzen Raum). Während Ellie die Sternenbrücke hinaufläuft, erklingt ihre erste gedämpfte `SpeechBox`-Stimme durch den Saal.
  5. **Erstes Gespräch & Erste Gabe:** Vor den Stufen beginnt das volle `DialogueBox`-Gespräch. Die Wächterin erklärt, warum sie eingegriffen hat, enthüllt ihren Namen und überträgt Ellie ihre erste **göttliche Fähigkeit** – die Läuterung des Schattenschritts zum **LICHTSCHRITT** (`ALT`).
* **Spätere Tode:** Danach ist die einmalige Rettung verbraucht – spätere Tode verhalten sich wieder regulär über `_respawn_after_delay` (eine erneute Rettung könnte später höchstens eine seltene Gabe oder Spätspiel-Fähigkeit sein).

---

## 5. Zugang & Rückkehr nach der Introduction

Nach dem ersten Besuch öffnet sich der Pfad über das bestehende Wegstein-Netz ([waystones.md](waystones.md)):

* **Hinweg (an jeder erwachten Statue):**
  * `E` an einer erwachten Statue öffnet wie gewohnt `WaystoneTravel` + die Reisekarte (`MapWaystones`).
  * Ganz oben/mittig über der Karte schwebt nun ein eigenes, golden gerahmtes Sternen-Siegel: **`STERNENSAAL`** (funktioniert auch schon dann, wenn erst **eine** Statue in der Welt erwacht ist!).
  * Halten von Mausklick oder `E` (~1,15 s) füllt den goldenen Lichtring, die Statue flammt auf und transportiert Ellie in den Sternensaal.
* **Rückweg:**
  * Am Ankunftskreis im Süden des Saals bringt `E ZURÜCKKEHREN` Ellie wieder vor die Statue zurück, von der sie gekommen ist (beim erstmaligen Rettungs-Besuch vor die zuletzt/nächstgelegene erwachte Statue).
  * *(Optional für später: Vom Ankunftskreis direkt eine andere erwachte Statue als Ziel wählen.)*
* **Speichern im Saal:** Wird im Sternensaal gespeichert oder getrennt, merkt sich `SaveGame` den sicheren Rückkehrpunkt (bzw. stellt sie sauber wieder in den Saal mit bekanntem Rückkehr-Ziel).

---

## 6. Göttliche Fähigkeiten & `SCHATTENSCHRITT` → `LICHTSCHRITT`

### 6.1 Prinzip: Läuterung statt separater Tastenflut
Ellie trägt bereits Kräfte der Leere in sich (beginnend mit `SCHATTENSCHRITT` auf `ALT`). Göttliche Fähigkeiten **verwandeln bestehende Kernfähigkeiten** oder verankern seltene Schutz-/Lichtmechaniken an entscheidenden Meilensteinen – ohne neue Hotbar-Slots oder klobige Extra-Tasten zu erzwingen.

### 6.2 Erste göttliche Fähigkeit: `LICHTSCHRITT` (ersetzt `SCHATTENSCHRITT` auf `ALT`)
* **Dauerhafte Verwandlung:** Nach dem ersten Gespräch im Sternensaal wird Ellies `SCHATTENSCHRITT` dauerhaft zu **`LICHTSCHRITT`** geläutert (`BlinkComponent` wechselt in den Licht-Modus).
* **Veränderte Darstellung im `Schleiergeflecht` (`F`):**
  * In [data/skills.json](data/skills.json) und `SkillTreeWindow` wird der bisher violette Knoten `shadow_step` von goldenen Linien durchbrochen und leuchtet fortan **türkis-gold** als `LICHTSCHRITT` – das sichtbare Zeichen, dass die Göttin den Griff der Leere über diesen Pfad gebrochen hat.
* **Optik & Audio:**
  * Statt violetter Leeren-Risse und `ARRIVE_TINT` in Violett löst sich Ellie in einen **gold-türkisen Sternenblitz** auf, zieht einen kurzen Bayer-geditherten Lichtschweif durch die Luft und erscheint am Ziel mit einem feinen goldenen Lichtring und hellem Kristallklang.
* **Mechanische Aufwertung (spürbar gegen die Leere):**
  * **Lichtblendung / Störung:** Schattenwesen, nahe an denen sie startet, durchquert oder neben denen sie landet, zucken kurz geblendet zurück (leichter Licht-Impuls / kurzer Unterbruch gegen schwächere Angriffe – ideal, um aggressiv durch Gegner oder vor Schockwellen hindurchzutauchen).
  * **Kurzer Sternenfunke:** Am Zielpunkt bleibt für ~1,5 s ein kleiner, echter `NightLight`-Schein bestehen (ein kurzer Atemzug Sicherheit in tiefster Nacht).
  * **Komfort-Plus:** Leichte Verbesserung gegenüber dem alten Schattenschritt (z. B. etwas kürzere Grund-Abklingzeit oder leicht höhere Reichweite); bestehende Boni wie die **Rissfeder** (`blink_cooldown` in `TalismanComponent`) bleiben voll kompatibel.

### 6.3 Ausblick auf weitere göttliche Fähigkeiten (spätere Meilensteine)
Für künftige Kapitel / Bosse / Statuen-Meilensteine bleibt Platz im gleichen System – z. B.:
* **Sternenschneide:** Abschluss-Schläge einer Schwertkombo senden eine schmale Lichtsichel mit Zusatzschaden gegen Schattenwesen.
* **Gnade des Ankers:** Ein starker Schutz gegen die Leere (z. B. ein lichtes Schild bei kritischer Wunde oder eine verstärkte Version der ersten Rettung mit sehr langem Cooldown).
* **Wahrer Blick:** Durchdringt Trugbilder/Nebel bei bestimmten Angriffen oder verbessert die Lichtwirkung von `Lichtschritt` weiter (inkl. späterer Nutzung der `shadow_echo_*`-Knoten über dem Lichtschritt im Skilltree).

---

## 7. Das Gaben-System (Gerüst für „mehr dazu später“)

Neben der festen Geschichte und den göttlichen Fähigkeiten erhält die Göttin am Thron eine eigene Interaktions-Option **`GABEN`** (getrennt von `SPRECHEN`), deren Innenleben wir später gezielt ausarbeiten:

* **Abgrenzung zu bestehenden Systemen:**
  * **Talismane (Esma):** Ausrüstung am Körper (Kette, Ohrringe, Armband).
  * **Zauberstäbe & Kristalle (Ilva):** Aktive Magie auf LMT/RMT in der Hotbar.
  * **Gaben (Göttin):** Übergeordnete, spirituelle **Segen / Schwüre**, die am Thron empfangen oder gewechselt werden (z. B. feste Anzahl aktiver Gaben-Plätze, freigeschaltet durch erwachte Statuen, bestandene „Prüfungen der Wächterin“ oder kosmische Opfergaben).
* **Drei vorbereitete Richtungen für später:**
  1. *Gaben der Nacht & des Lichts* (z. B. Schutz gegen Dunkelheit/Nebel, mildere Nächte, Heil-Impulse an Wegsteinen).
  2. *Gaben der Reise & Anmut* (z. B. Ausdauer, Lichtschritt-Modifikatoren, Welt-Interaktionen).
  3. *Gaben des Bundes* (z. B. Koop-Synergien, Kampf-Segen gegen Schattenwesen und Bosse).

---

## 8. Mehrspieler- & Speicher-Design (1–4 Spieler)

Gemäß Shadowspores **host-autoritativer Multiplayer-Architektur**:
* **Gemeinsamer Sternensaal:** Der Sternensaal existiert einmal als fester Pocket-Slot der Welt. Mehrere Spieler können ihn gleichzeitig über Statuen betreten und sich gemeinsam vor dem Thron begegnen. Die Beleuchtungsstufe des Saals richtet sich nach dem gemeinsamen Weltzustand `Waystones.awake`.
* **Persönliche Introduction & Rettung:**
  * Jeder Spieler erlebt seine **erste Rettung vor dem Tod** eigenständig (sobald mindestens 1 Welt-Statue wach ist und dieser Spieler noch nicht eingeführt wurde).
  * Der Host entscheidet in `HealthComponent._warded` (bzw. dem Rettungs-Controller), löst die Sequenz per gezieltem RPC für diesen Spieler aus und speichert `goddess_introduced` pro Spieler.
* **Persönliche göttliche Fähigkeiten & Gaben:**
  * `LICHTSCHRITT` und künftige göttliche Fähigkeiten/Gaben gehören jeweils dem einzelnen Spieler (host-validiert und im Spieler-Save gespeichert); das visuelle/akustische Abspielen des Lichtschritts wird wie bei `BlinkComponent` sauber an alle Peers synchronisiert.

---

## 9. Vorgeschlagener Umsetzungs-Fahrplan (für später)

Falls wir das System Schritt für Schritt bauen, bietet sich diese Reihenfolge an:
1. **Schritt 1 – Sternensaal-Prototyp & Kosmos-Shader:** Pocket-Space mit offenem Marmorboden, Sternen-Parallax-Hintergrund, Thron-Platzhalter und Rückkehr-Anker.
2. **Schritt 2 – Die Göttin (Art & Portrait):** `tools/art_goddess.py` (Ellipsoid-Pipeline wie `art_waystone.py`, Thron-Posen + unlit Kristallkranz) + `103×153` Dialogportrait nach [dialogue_art.md](dialogue_art.md).
3. **Schritt 3 – Reise durch Statuen & Rettungs-Trigger:** `STERNENSAAL`-Siegel in `MapWaystones` / `WaystoneTravel`, einmalige Todes-Rettung über `HealthComponent._warded` + `SaveGame`-Persistenz (inkl. Dev-Testknopf für direkten Sprung in die Introduction).
4. **Schritt 4 – Erste göttliche Fähigkeit (`LICHTSCHRITT`):** Erweiterung von `BlinkComponent`, neue `Unlit`-Lichtschritt-FX + Sounds, Stagger/Blend-Effekt gegen Schattenwesen und visuelle Verwandlung im `SkillTreeWindow`.
5. **Schritt 5 – Gaben-System (Detailkonzept & Umsetzung):** Sobald du die konkreten Gaben definierst, folgt das eigene Gaben-Konzept und das UI am Thron.
