# Die Steinstadt im Westen – Konzept „HALLGRAT"

> Arbeitsname **Hallgrat** (Hall = Nachklang, Grat = Bergrücken). Alle Namen, Texte und Zahlen sind **Platzhalter und Vorschläge**, nichts davon ist gebaut. Dieses Dokument ist eine Ideensammlung zum gemeinsamen Aussortieren, kein Beschluss. Es folgt der Regel aus CLAUDE.md: Systeme, die nicht besprochen sind, werden nicht gebaut.

## 0. In einem Absatz

Im äußersten Westen, wo das Land in die Leere übergeht, steht auf einem terrassierten Felsrücken eine **alte, bewohnte Steinstadt**: Stützmauern statt Klippen, Treppengassen statt Straßen, Kristalladern im Fels, die früher die Lampen der Stadt speisten und jetzt nur noch flackern. Sie war einmal Sitz der Steinsetzer-Gilde und Hüterin eines Wegsteins. Seit die Schatten kamen, hat sie sich eingeigelt, den unteren Teil aufgegeben, ein Viertel hinter einer Schattenmauer verloren und lebt von Gewohnheit, Stolz und einem Glockenschlag zur Dämmerung. Ellie kommt als Fremde, **weckt den Wegstein im Herzen der Stadt**, und eine Welle aus Licht läuft durch das Pflaster, die Leitungen im Stein und jede Laterne: die Stadt leuchtet zum ersten Mal seit Jahren. Danach ist sie ein Ort zum Wiederkommen: Handwerk, Archiv, Gasthaus, Markttage, Geschichten, ein verschlossenes Viertel, ein Glasbruch unter dem Berg und ein Blick über die Mauer in die Leere.

---

## 1. Abgrenzung zu Glimmrast (Ellies eigene Stadt)

| | **Glimmrast** (Spielerstadt, `town.md`) | **Hallgrat** (Weltstadt) |
|---|---|---|
| Herkunft | von Ellie gebaut, wächst | fest in der Welt, handgebaut, **alt** |
| Material | Holz, Schiefer, Eisen, neu | Stein, Moos, Patina, wenig Holz |
| Gefühl | Aufbruch, Hoffnung, fragil | Würde, Erinnerung, Verschleiß, stille Sturheit |
| Licht | Lichtkreise, die Ellie setzt | uralte **Leitsteine**, die sie wieder anschließt |
| Zustand | nach Spielerhandlung | **Stadtstufen** (0 erstarrt … 4 strahlend), nach Story und Taten |
| Bewohner | ziehen ein, gehören der Spielerin | gehören sich selbst; kommen und gehen, ziehen ausnahmsweise um |
| Technik | `TownManager`, Pieces, Free Placement | handgebaute Karte, `ground.json`, Interiors, Settler-Pläne |

Faustregel: **Glimmrast ist das, was Ellie tut, Hallgrat ist das, was sie findet.** Hallgrat ist nie Konkurrenz, sondern Gegenüber: ein Ort, der zeigt, wie eine Stadt aussieht, die schon alles verloren und trotzdem nicht aufgegeben hat. Und sie liefert, was Glimmrast fehlt (Steinbau, Kristall, Wissen, Handel).

---

## 2. Standort

### 2.1 Entscheidung (Empfehlung): **der Glaskamm** im Nordwesten der Glasklippen

Aus `relief.png`, `relief.json`, `land_sdf.png` ausgelesen (Näherungswerte, im Spiel noch nicht abgelaufen):

| Merkmal | Wert |
|---|---|
| Lage | Hügelrücken bei Kachel **(121–190, 295–400)**, Mitte etwa **(150, 350)**, Überregion *Glasklippen* (Region 7) |
| Entfernung | rund **715 Kacheln** vom Hut (786, 676), rund **410** vom Spielstart (463, 616); zu Fuß 1,5 bis 2,5 Minuten Sprint |
| Gipfelplateau | Ebene 3, rund **1 250 Kacheln** (≈ 44 × 45, unregelmäßig, 704 × 720 px: etwa ein Bildschirm breit und zwei hoch) |
| Hangterrassen | Ebene 2 ≈ 1 650, Ebene 1 ≈ 2 600 Kacheln, in 3er-Stufen, mit 3-Kachel-Wänden dazwischen |
| Aufstiege | 17 vorhandene Verbinder: **4 Rampen, 13 Felsstufen**; 4 führen nach Osten hinunter, je einer bis drei nach Norden, Süden und Westen |
| Vorland | im Osten die größte freie Ebene-0-Fläche des Westens (Scheibe r ≈ 50 um (237, 344)), flach, ohne Wasser, ideal für Vorstadt, Felder, Karawanenplatz |
| Westrand | zwischen Plateau und Leere nur ein **12-Kachel-Streifen** Küstenland: die Westmauer steht *am Weltrand* |
| Wegstein | **WÄCHTERIN DES GLASKAMMS** (142, 355) steht schon auf dem Plateau: sie wird das Herz der Stadt |
| Größe | gesamtes Gelände ≈ 5 500 Kacheln ≈ 22 Bildschirme: „nicht zu riesig", 35 bis 50 Gebäude, davon rund 10 begehbar |

Warum hier:

- **Das Gelände liefert die Stadt schon.** Die Terrassen *sind* Stützmauern, die Rampen *sind* Tore. Wir müssen kein Relief neu bauen, nur umdeuten und überbauen.
- **Thema passt:** Glasklippen = Stein mit Kristall. Der Leerenbrecher wurde laut `leerenbrecher.md` zuerst „an den Felsen der Glasklippen" gesichtet.
- **Am Weltrand:** die Westmauer blickt in die Leere (`VoidEdge`: nachts Augenpaare in der Tiefe). Das ist ein Bild, das keine andere Stadt haben kann.
- **Weit weg von Glimmrast:** ein echtes Reiseziel, ein Grund für Wegsteine, Westweg und Karte.

### 2.2 Alternativen (falls dir der Ort nicht gefällt)

| | Ort | Für | Gegen |
|---|---|---|---|
| **B „Der Klippenstock"** | Plateau (190–260, 615–720), Ebene 3, ca. 70 × 100, Wegstein *Wächterin der Klippen* (215, 660) | deutlich größer, näher (≈ 550 Kacheln vom Hut), Küste im Westen | eher zu groß, kein Randgefühl, die Stadt würde den Hügel ganz füllen |
| **C „Das Flachtal"** | freie Ebene 0 um (194, 430), r ≈ 37, mit einzelner Hügelinsel (150–175, 455–480) | maximale Baufreiheit, Burg auf der Insel | keine Terrassen, Stadt „klebt" nur auf Wiese, weniger Steinwelt-Gefühl |

### 2.3 Relief: umdeuten statt neu backen

- Das Relief ist **eingefroren und gebacken**. Die Plateau-Wände tragen teils Stil 1 (Fels) und 3 (Kristall), werden aber in `Relief._apply_world_biome` zur Laufzeit auf Fels/Gras gedrückt (alles ≥ 2 wird 0 oder 1).
- **Idee: Stadt-Rechteck als Ausnahme** (wie beim Hexenwald `own_biomes`, aber ohne eigenes Biom): in einem Rechteck um den Glaskamm bleiben die Wandstile erhalten bzw. werden vom Baker auf **Stil 2 (Mauerwerk)** gesetzt, Rampen/Felsstufen werden **Treppen (Stil 3)** mit Brüstungen. Nur Stil-Bytes ändern sich, **Höhen, Geometrie und Kollision bleiben bytegleich** (Test wie `test_hexenwald_terrain.py`: Altland identisch). Kein Neubacken der Welt.
- Optional für später: ein kleines Plateau-Rechteck um das Wegstein-Forum auf Ebene 3 flachlegen (der Baker kennt `START_RECT`).
- **Offen, zu prüfen:** wie das Mauerwerk-Wandbild im Shader (`relief.gdshader`, Ziegelreihen, Moosfugen) bei Stadtzoom wirkt. Das Stilmaterial ist da, aber noch nie in Serie gesehen.

### 2.4 Der Weg dorthin: „Der Westweg"

Der Westweg ist die erste wirklich lange Reise im Spiel und soll sich wie eine anfühlen:

- Ein gebackener Pfad (`paths` in `ground.json`, `bake_ground.py`, wie der Fußpfad und `hexenwald_path`) vom Startgebiet über die flache Ebene 0 nach Westen, ≈ 400 Kacheln, ohne Ebenenwechsel.
- **Meilensteine** alle 50 Kacheln (`Signpost`-Variante, mit Zahl, die zum Stadtnamen herunterzählt: 350, 300, … 50). Wer sie liest, bekommt eine Zeile; ab Stein 100 sind sie sauberer gemeißelt: die Stadt wirkt voraus.
- **Raststationen:** zwei verfallene Steinhütten am Weg (Feuerstelle, `CampfireSeat`, Lore-Notiz), ein umgestürzter Karren (`art_wagon.py`-Wrack), ein Brunnen mit Inschrift.
- **Vorboten:** ab Meile 150 stehen immer öfter alte **Leitsteine** am Weg, kleine Kristallstümpfe, tot. Ab Meile 50 flackert einer. Wer sie anstupst, hört einen Ton (Klang-Motiv, siehe 8.1).
- Die Wegsteine **Wächterin der Lichtung** (373, 858) und **der Klippen** (215, 660) liegen in der Nähe der Anreise; Hallgrats Statue ist der Schnellreisepunkt für den Rückweg.

---

## 3. Geschichte der Stadt (Lore für Texte und Inschriften)

*Alles Platzhalter, aber so gebaut, dass es zu `valdric.md`, `torben.md`, Wegsteinen und Leerenbrecher passt.*

1. **Gründung (vor ca. 300 Jahren):** Steinsetzer, Wanderhandwerker, finden im Glaskamm eine Ader aus **Klangstein**: Gestein, das Licht speichert und Töne trägt. Sie bauen um die Ader eine Stadt, und um den Gipfel herum die Statue der **Wächterin** (der Wegstein), der sie ihr Licht verdanken.
2. **Blütezeit:** Hallgrat ist Steinmetz-, Glas- und Lampenstadt der Küste. Straßen führen nach Osten; Karawanen bringen Holz und Getreide, nehmen Glas, Lampen und Quader mit. Der **Orden vom roten Mantel** (Valdrics Orden) unterhält eine **Rothalle** als Garnison; die Stadt zahlt, der Orden schützt.
3. **Die Stille Zeit:** Die Schatten kommen aus der Leere (die Westmauer ist die erste Linie). Der Orden hält die Mauer. Die Ader beginnt zu verstummen: Die Stadt „klingt" nicht mehr, ihre Leitsteine erlöschen von unten nach oben (zuerst der Fuß, dann die Staffeln).
4. **Der Fall des Westviertels:** Ein Durchbruch frisst das **Westviertel** (heute „Verlorenes Viertel"): die Stadt versiegelt es mit der **Schwarzen Mauer**, ein Teil des Ordens bleibt drin. Der Orden zerfällt (hier verweist Valdrics Schweigen hin: er weiß mehr, als er sagt).
5. **Heute:** rund 40 Menschen leben auf Oberstadt und Staffeln. Der Fuß ist Geisterviertel. Die Karawanen kommen nur noch selten. Die Glocke wird noch jeden Abend geschlagen, nicht aus Hoffnung, sondern aus **Brauch**.

**Verborgene Schicht (Spielerwissen):** Der Wegstein ist nicht nur Teleporter, sondern **Stimmgabel** der Stadt: Alle Leitsteine sind auf ihn gestimmt. Wer ihn erweckt, bringt die Stadt wieder in Takt. Aber die Ader selbst ist **mit der Leere verwachsen** (violette Maserung): Sie leuchtet nur, weil sie etwas von der Leere in sich trägt. Die Stadt leuchtet mit dem Stoff, der sie bedroht. (Anschluss an das Weltthema: Leere nicht nur Feind, sondern Material. Entscheidung bei dir.)

---

## 4. Aufbau der Stadt (Schnitt von West nach Ost)

```
 LEERE │ Randpromenade │ Westmauer │ OBERSTADT „Die Stille" (E3) │ STAFFELN (E2→E1) │ DER FUSS (E0) │ Vorland
 Void  │  12 Kacheln   │ Brüstung  │ Forum, Wegstein, Mondturm   │ Handwerk, Wohnen │ Markt, Tor    │ Felder
       │ „Letzte       │ Wächterwg │ Hüterhalle, Rothalle        │ Gärten, Zisternen│ Gasthaus      │ Karawanen-
       │  Brüstung"    │           │                              │                  │ Karrenhof     │ platz
```

Schwarze Mauer und **Verlorenes Viertel** liegen an der Nordwestflanke (Ebene 1–2); der **Glasbruch** hat seinen Zugang am Nordfuß; **Zisternen und Katakomben** sind Innenräume im Hügel (Interiors).

### 4.1 Die fünf Bezirke

**① Der Fuß (Unterstadt, Ebene 0, Osten) – „die Öffnung zur Welt"**
- **Osttor** an der Karrenrampe (≈ (179, 371)): zwei Torhäuser, eine eingelassene Winde, ein Fallgatter, das nie fällt, weil es verrostet ist (am Anfang offen; später ein Rätsel, siehe 10).
- **Steinmarkt:** großer gepflasterter Platz mit Stein-Marktständen (nur Tischplatten und Wetterdächer aus Leinen), Brunnen mit Wasserspeier, **Waage** (Steinwaage, zum Einwiegen von Fängen und Erz).
- **Karrenhof/Karawanserei:** offener Hof mit Brunnentrog, Stallbuchten (leer, später Karawanentiere, kein Tier wird verletzt), Lagerhäuser.
- **Die Stallungen** (Beschluss 2026-11-13): ein großer Steinstall gleich neben dem Karrenhof, mit Heuboden, Sattelkammer, acht Buchten und einer Koppel dahinter. Er wird **später der Ort der Reittiere**. Ellie hört um **Stufe 15** zum ersten Mal davon: Jorun erzählt es ihr, wenn er mit der Karawane in Glimmrast steht. Bis dahin ist der Stall da, aber leer und verschlossen.
- **Gasthaus „Zum Stillen Stein"** (Interior): Kamin, lange Steintische, Gästezimmer, kleine Bühne.
- **Terrassenfelder** an der Nordost-Flanke: Linsen-, Rüben- und Kräuterbeete mit Trockenmauern, ein halb verlassener Windmühlturm (Wind aus `WorldWind`).
- **Geisterstraße:** leere Häuser mit zugenagelten Läden, ein Bäcker ohne Bäcker (den Ofen gibt es noch), Wäscheleinen mit Fetzen. **Hier beginnt Stadtstufe 1**: nach und nach öffnen sich Läden.

**② Die Staffeln (Terrassen, Ebene 1–2) – „das Herz der Arbeit"**
- Drei Stufen übereinander, verbunden durch **Treppengassen** (Rampen/Treppen, Stil 3), **Torbögen** und **Stützmauern**; Häuser sind in den Fels gesetzt (Rückwand = Fels, Vorderfront = Mauerwerk).
- **Steinmetzhof** (Odriks Werkstatt, Interior + Hof mit Quadern, Kran und halbfertigen Statuen).
- **Glasschleiferei** (Interior: Schleifsteine, Kristalle, Lichtbrechung als Boden-Gimmick).
- **Lampenmacherei** (Interior: Laternenreihen, Glühfäden aus Klangstein).
- **Färberei und Wasserspeier-Gasse:** farbige Tücher an Fassaden (Wimpel, Tuch-Sway wie `sway_rows`).
- **Hängende Gärten:** Dachgärten auf den Staffeln, die unteren Dächer sind die Gärten der oberen (Kräuter, Moos, Glimmkappen, Flora-Reuse).
- **Zisternen-Eingang:** ein Rundbogen mit Wasserlauf; führt unter den Berg.
- **Kleine Bühne:** eine Nische mit Bank, wo abends gesungen wird.

**③ Die Stille (Oberstadt, Ebene 3) – „Würde und Nachhall"**
- **Das Forum:** runder Platz mit **Wegstein-Statue** (Mutterstein) in der Mitte, Leylines im Pflaster (Reuse `art_waystone_ground.py`: poliert, wenn erwacht), umlaufende Arkaden.
- **Hüterhalle** (Interior): Ort der Wächterin-Hüterinnen; Wandmalereien in Stein, Kerzenreihe, Stille.
- **Das Steinarchiv** (Interior, in den Fels getrieben): Regale aus Fels, Lesepulte, Karten, Kristall-Lampen; Lore-Sammelpunkt.
- **Der Mondturm** (Interior bis zur Spitze): Observatorium, Glocke, Aussichtsplattform (Mondphasen, Nachtvorhersage, siehe 8.3).
- **Die Rothalle** (Interior): ehemalige Garnison des roten Ordens: verstaubte Banner, Waffenständer, ein verlassener Tisch, unter dem Boden eine Tür.
- **Ratsstube und Vogtshaus:** Siegel, Stadtgesetz, Karte der Stadt.
- **Der Brunnenhof:** der einzige Springbrunnen mit echtem Wasserlauf, Zuflucht der Kinder.

**④ Die Randpromenade (Westmauer) – „der Blick ins Nichts"**
- Eine schmale Mauerstraße am Weltrand: **Wehrgang** mit Zinnen, drei Wachposten, **Leerenfenster** (Nischen mit Bank, durch die man in die Leere schaut), ein **Gedenkgarten** hinter einer Eisenpforte (Gräber, Namenswand).
- Nachts: die **Letzte Brüstung** mit eingelassenen Schalen, in denen Leitsteinlicht brennt; die Leere atmet. Wachen starren hinaus. Der atmosphärisch stärkste Ort der Stadt.

**⑤ Der Untergrund – „was die Stadt trägt"**
- **Zisternen** (Wasserhallen mit Säulen, Kristalle, Tropfen, Fischlicht: ein Bild für sich).
- **Katakomben / Steinsetzergräber:** schmale Gänge, Namen in Stein, **Flüstergang** (Akustik).
- **Der Glasbruch:** aufgelassene Kristallmine, Zugang am Nordfuß; hier schlägt das Herz der Ader (siehe 7.3).
- **Der Innenaufzug:** ein Schacht mit Winde, der Fuß und Oberstadt verbindet (Abkürzung, wenn repariert).

### 4.2 Größenordnungen (zum Prüfen, Person = 52 px, Tür ≈ 28 × 40 px)

| Bauwerk | Fläche (px) | Anzahl |
|---|---|---|
| Wohnhaus klein | 96 × 80 | 18–22 |
| Haus mit Laden/Werkstatt | 128 × 96 | 8–10 |
| Halle (Hüter, Rot, Archiv) | 192 × 128 | 3 |
| Mondturm | 80 × 160 (hoch) | 1 |
| Torhaus | 96 × 96 | 2 |
| Platz | 256 × 256 (Forum), 320 × 224 (Markt) | 2 |
| Innenräume | 256 × 232 bis 384 × 256 (Hut: 256 × 232) | ≈ 10 |

---

## 5. Look and feel

**Palette:** die vorhandene blauviolette **STONE-Rampe** (Fels, Schiefer; wie `art_stone.py`), dazu warmes **Sandstein-Ocker** für Fassaden (Sonnenseite), **Weinrot** (Orden, Banner, Vorhänge), **Kristallviolett und Türkis** (Leitsteine; Türkis = Leben/Wegstein, Violett = Leere in der Ader), Moos- und Efeugrün in den Fugen. Kein Neu-Rot, kein Gold außer an Siegeln.

**Architektur:** schwere Rundbögen, Spitzbögen nur bei Hallen, **Keilsteine sichtbar**, Treppen mit abgetretener Mitte, Wasserspeier mit Tiergesichtern, steile Schieferdächer, **Dachreiter** und Zwiebelkuppeln nur am Mondturm. Häuser lehnen am Fels, Gassen sind schmal (24 bis 40 px), damit man sich *umschlossen* fühlt.

**Alter sichtbar machen (aus `town.md` „wear"):** abgerundete Kanten, gesprungene Fensterstürze, wieder aufgemauerte Flicken in anderem Stein, Moos in Fugen, Efeu, ausgetretene Stufen, Ruß um Kamine, Risse, ausgeblichene Banner. Zwei Zonen unterschiedlich verwittert: **Fuß** (verlassen: Moos, Spinnweben, abgeblättert) vs. **Stille** (gepflegt, aber alt).

**Rendering:** gleiche Ellipsoid-Pipeline wie Hütte, Zeche und Hexenturm (`hut_lib`-Prinzip: Bänder, Maserung, Moos, Adern); eigene Module `art_hallgrat_*.py`. **Art geht an den Terra-Agenten (Nutzerwunsch)**, Integration und Prüfung bleiben bei mir.

**Licht:** Leitsteine als `NightLight`-Quellen (kühles Türkis-Weiß, im Fels violette Adern), warme Fensterlichter (aus der Hütte bekannt), Schalen auf der Westmauer; **Kristalladern** in den Wänden glühen nachts (Reuse `wall_glow_pass` des Relief-Shaders, wenn Stil 3 erhalten bleibt).

**Wetter und Tageszeit (nutzen, was schon da ist):**
- Regen läuft in **Rinnen** die Terrassen hinab, Wasserspeier spucken, Pfützen in den Pflasterspalten (`g_puddle`).
- Gewitter: der **Blitzfang** (eiserne Spitze auf dem Mondturm) zieht Blitze an (Glasklippen haben im Wetterkonzept schon „Blitzanziehung (Optik)").
- Wind: Wimpel, Wäsche, Windmühle.
- Morgen: Nebel in den Gassen, Tau auf Stufen; Abend: goldenes Licht in der Westmauer-Nische.

**Klang:** Stein-Schritte (Oberfläche `stone` gibt es), **Halleffekt in engen Gassen** (Audio-Zonen, „Hallraum"), Glocke, Schleifstein, Hammer auf Meißel, Wasser in Rinnen, Wind in den Zisternen, ferne Kinder. **Das Stadt-Motiv** (siehe 8.1): vier Töne, die nur im Leitstein-Klang vorkommen.

---

## 6. Bewohner (Dossiers kommen später, Namen sind Platzhalter)

*Figuren, Portraits und Dialogtexte entstehen bei den dafür vorgesehenen Agenten. Hier nur Rolle und Haken.*

| Name | Rolle | Haken / Beziehung zu Ellie | Besonderheit |
|---|---|---|---|
| **Brann** | Torwächterin, alte Soldatin | misstrauisch, später loyal; testet Ellie mit einem Rätsel statt Waffe | kennt jeden Gast beim Namen, wenn er einmal war |
| **Ilvane** | Hüterin der Wächterin (Wegstein-Statue) | spricht in Rätseln; kennt Ellies Statuen-Erweckungen („Du hast die Hand gelegt") | einzige, die weiß, dass der Stein antwortet |
| **Odrik „Meißelbart"** | Steinmetzmeister | lehrt Steinbau (Rezepte für Glimmrast) | **baut an einer Statue**, deren Gesicht sich je nach Story verändert (8.7) |
| **Tamsa** | Glasschleiferin | frech, schnell, liebt Kristall; stellt Talisman-Steine her | will ein „echtes Leitstein-Herz" (Questkette) |
| **Pim** | Lichtknecht, 14, entzündet die Laternen jeden Abend | Ellie begleitet ihn auf der Runde (Ritual-Szene) | Hallgrats Herzschlag; ohne ihn bleibt die Stadt dunkel |
| **Sebald** | Archivar | pedantisch, sammelt Inschriften; gibt Karten | tauscht Fragmente gegen Funde |
| **Hedda** | Wirtin | Hausmannskost, Gerüchte, Rezepte | **Küchenbuch**-Anbindung (Rezepte, die Ellie später kochen kann) |
| **Jorun und Familie** | Karawanenführer (wechselnd da) | bringen Fernes (Holz, Samen, Nachrichten aus dem Osten) | kommen alle paar Tage, wenn der Weg offen ist |
| **Perrin** | blinder **Stimmer**, hört Resonanz | Questgeber der Stimmsteine (8.1) | kann Leitstein-Töne hören, die Ellie nur sieht |
| **Hauptmann Corvin** | letzter Rotmantel der Garnison | kennt Valdric (oder tut so) | Story-Schlüssel (siehe 12, **Entscheidung**) |
| **Vogt Maeve** | Stadtoberhaupt | will Ordnung, fürchtet Fremde, hat ein Geheimnis (Schwarze Mauer) | gibt offizielle Aufträge |
| **Die Kinder** (Moos, Fink, Lia) | spielen auf Treppen, verstecken Dinge | zeigen Abkürzungen und Verstecke | tragen kleine **Funde** (Sammelziele) |
| **Schiefer** | die Stadtkatze | schläft auf der warmen Esse | streichelbar (kein Tier wird verletzt) |

**Tagesplan** (Reuse `Settler`: Plätze sind reine Funktion der Uhr): Morgen Läden öffnen, Mittag Markt, Dämmerung **Lichtrunde** mit Pim und Glockenschlag, Nacht: Stadt zu, Wache auf der Westmauer, Gasthausgesang, Perrin am Mondturm.

**Besuch von außen (optional):** Gustav (Steinmetz-Neugier), Valdric (stumm vor der Rothalle), Esma (Schmuck und Kristall). Wer in Glimmrast wohnt, aber hier handelt, nutzt `register_person/outpost` (schon für Esma gebaut).

---

## 7. Orte, die man besucht (Die „Wow-Orte")

### 7.1 Das Forum der Wächterin (Ankunft und Erweckung)
Erste Szene: Ellie steigt die Rampe hinauf, ein Stückchen Stadt nach dem anderen. Alles dunkel, Läden zu, aber Glocken. Auf dem Forum steht der Mutterstein, überwachsen, die Hüterin wartet. Ellie legt beide Hände (die bekannte `begin_touch`-Animation) auf den Stein, und die **Welle** (Reuse `waystone_awaken`, Boden-Wave) läuft vom Sockel **durch das Pflaster, die Leitsteine, die Laternen, die Kristalladern in den Wänden** bis zum Westrand. Jede Laterne springt an, wenn die Welle sie erreicht (Entfernung → Zeitversatz, wie bei den Bodenkristallen). Die Stadt hält den Atem an, dann beginnen die Fenster zu leuchten. *Das ist die große Szene des Gebiets.*

### 7.2 Die Westmauer / Letzte Brüstung
Ein Ort zum Sitzen (`CampfireSeat`-Pipeline für Mauerbänke), zum Nachdenken, für Boss-Foreshadowing, für das Treffen mit Corvin. Nachts mit Augenpaaren in der Leere; tagsüber ein ruhiges Gold-Violett.

### 7.3 Der Glasbruch (Mini-Dungeon)
Kristallmine unter dem Nordhang. **Nutzt das Minensystem** (`MineManager`, `MineGenerator`): eine eigene Zone „Glas" (Terrain-Palette, Clutter, Gegner in `data/mine.json`), 3 bis 4 kleine Ebenen. Besonderheit: **die Ader singt**. Je tiefer, desto lauter der Klang, desto mehr Gegner „hören" (`VoidListener`!). Ziel: das **Herz der Ader**, ein riesiger Kristall, der entweder repariert (Stadt leuchtet stärker) oder **abgeschaltet** werden kann (Stadt dunkler, Leere weniger gereizt). **Entscheidung für spätere Story.**

### 7.4 Das Verlorene Viertel
Gesperrt hinter der **Schwarzen Mauer**, einem breiten, feucht schimmernden Streifen Schattenfraß (nutzt `ShadowPatch`-Optik in groß, statisch). Dahinter: ein zerbrochenes Viertel, Schatten in den Fugen, offene Häuser, Spinnen, Horcher, ein **Leerenbrecher** (der Gebietsgegner aus `leerenbrecher.md`) als Mini-Boss im Hof der alten Kaserne. Ziel: ein verlorener Gegenstand (Siegel, Banner, Talisman) und die Wahrheit über den Orden. **Mehrstufig**: erst ein Fenster hinein (Aussicht), dann Durchbruch.

### 7.5 Die Zisternen
Unterirdische Halle mit Säulenreihen, Wasserstand, Kristallen, **schwimmen möglich** (Schwimmsystem existiert) in einem Teil; das Wasser ist **die Wasserquelle der Stadt**: ohne sie keine Fontäne, kein Bad, keine Wäscherinnen. Leitstein hier sorgt für Fischlicht. Ort für Rätsel (Wasserstand heben/senken), Schatzkiste, ein Geheimgang in den Fuß.

### 7.6 Der Mondturm
Spiralstiege (wie `witch_stairs`), mehrere Stockwerke (Observatorium, Glockenstube, Vorhersage-Tafel), oben **Plattform** mit Fernblick (Kamera zoomt aus). Von hier sieht man die Karte des Westens, Leitsteine auf dem Land leuchten wie Sterne (Teil der Karte, siehe 8.5).

### 7.7 Die Gedenkmauer
Eine lange Mauer mit Nischen und Kerzen. Jede Nische ein Name. Ellie kann **Namen hinzufügen**: gefallene Bewohner aus ihrer eigenen Stadt, bezwungene Bosse, ein Tier, das sie begleitet hat. Je mehr Kerzen, desto wärmer das Licht dort. Ein stiller Ort, der den Spielverlauf spiegelt.

---

## 8. Signature-Ideen (das „richtig Coole")

### 8.1 **Die singende Stadt** (Leitmotiv und Rätsel)
Der Klangstein trägt Töne. Jeder Leitstein hat einen **Ton**; zusammen ergeben sie den Akkord der Stadt. Perrin hört, welcher Stein „falsch" klingt. **Stimmsteine-Quest:** Ellie läuft durch die Stadt, schlägt **sieben Stimmsteine** an (Ton hören, Reihenfolge merken; kein Zeitdruck, kein Minispiel-Zwang), bringt den Akkord zurück, und das Licht der Stadt steigt Stufe um Stufe. Gleiches Motiv (vier Töne) in Wegsteinen, Glocke, Musik. **Nutzen:** Klang statt Zahl als Fortschrittsanzeige; spielt mit der bestehenden Hör-/Geräuschmechanik (Horcher reagieren auf Lärm).

### 8.2 **Die Lichtrunde** (Ritual)
Jeden Abend entzündet Pim mit einer langen Stange die Laternen in fester Reihenfolge (Fuß → Staffeln → Stille) und die Glocke schlägt. Ellie kann **mitgehen** und selbst entzünden (E auf die Laterne, kurze Animation, Reuse `B9 Lichtpfosten anzünden`). Die Stadt wird dadurch **Stück für Stück sichtbar**: ein Anblick, den man abends sucht. Wer die Runde verpasst, sieht die Stadt im Dämmer. Später ersetzt Ellie Pim an Festtagen.

### 8.3 **Der Mondturm und die Nachtvorhersage**
`TimeManager.moon_phase()` und `NightDirector` kennen Mondphasen und Sondernächte (flood, silent, fog, storm). Der Turmwächter liest daraus: **eine Tafel zeigt die nächsten drei Nächte** (Mondphase, Sondernacht, empfohlene Stufe), Ellie kann sich vorbereiten. Gibt dem Westen einen echten Nutzen für das Nachtsystem. Kostenlos, kein neues Balancing. *(Idee, nicht beschlossen: Vorhersage nur nach Quest.)*

### 8.4 **Die Stadt wird, was Ellie tut** (Stadtstufen)
Stadtstufen 0–4 hängen an Flags und Taten, nicht an Zeit:

| Stufe | Name | Auslöser | Sichtbar |
|---|---|---|---|
| 0 | **Erstarrt** | Ankunft | dunkel, Läden zu, wenige Menschen, Glocke |
| 1 | **Erwacht** | Wegstein erweckt | Leitsteine an, Fuß hell, Läden öffnen, Kinder draußen |
| 2 | **Belebt** | Stimmsteine / Lichtrunde | Markt, Karawanen, Gasthaus voll |
| 3 | **Verbunden** | Westweg offen, Glimmrast-Handel | Meilensteine glimmen, Handelsroute, Festtage |
| 4 | **Strahlend** | Ader repariert, Schwarze Mauer fällt | Westviertel offen, Festtage, Gäste aus dem Osten |

Technisch: pro Stufe ein Satz Bild-Zustände (Fensterlicht an/aus, Läden auf/zu, Wimpel, Moos-Overlay) wie beim `wear`/`renewed`-System der Hütte (`_reskin`), kein zweites Weltbild. **Host entscheidet**, Zustand wird gespeichert und an Joiner gesendet.

### 8.5 **Karte als Spielzeug**
- Der Archivar verkauft **Kartenfragmente** (Reveal der Nebelzonen im Westen: `MapDiscovery.reveal_disc`).
- Auf dem Mondturm ist **das ganze Westland sichtbar**: ein großes Reveal beim ersten Mal.
- Leitsteine auf dem Land werden zu **Karten-Symbolen**: jeder reparierte glimmt (Stadtstufe zeigt Fortschritt als Sternkarte).

### 8.6 **Hängende Gärten und Stein-Bauweise für Glimmrast**
Steinmetz Odrik lehrt Glimmrast Stein-Bauwerke (die Spielerstadt ist Holz): Rezepte für **Steinhaus, Torbogen, Mauerstück, Steinbrunnen, Pflasterplatten, Steintreppe**. Als `unlocks` in `recipes.json` (gleiches Muster wie `unlocks: "farming"`), Vertrauen (`trust`) wie bei Gustav. Dadurch **gibt Hallgrat der Spielerstadt Material**, und die Stadt wirkt nach dem Besuch anders. *Wichtigste Verbindung zwischen beiden Städten.*

### 8.7 **Odriks Statue**
Im Steinmetzhof steht ein halbfertiges Werk, ein Gesicht in Stein. Es wird **über die Spieltage** und Story-Marken fertiger (Meilenstein-Zustände). Das Gesicht gehört jemandem, dessen Namen Ellie erst spät erfährt (Wächterin selbst? Valdric? ein gefallener Hauptmann?). Ein stiller Zähler für den Spielverlauf ohne Pop-up. *Entscheidung: wessen Gesicht.*

### 8.8 **Die Wächterin hört zu** (Wegstein-Vertiefung)
Nach der Erweckung kann Ellie am Mutterstein **etwas fragen** (kurze Auswahl, drei Themen: Stadt, Leere, Ellie). Die Antworten sind Stein-Stimme (kurze Sätze, Echo), aber jedes Mal etwas klarer. Hängt an der bestehenden Wegstein-Berührung (`begin_touch`).

### 8.9 **Das Stadt-Gedächtnis (Inschriften-Sammelbuch)**
Überall in der Stadt, am Weg und im Untergrund liegen **Inschriften** (30–40 Stück): Gedenkplatten, Meisterzeichen, Kinderkritzeleien, Stadtgesetze, Spottverse. Jede lesen (E) = eine Zeile + Eintrag in ein Buch (`InscriptionBook`, persistiert wie `FishBook`/`CookingBook`). Sebald bewertet Vollständigkeit (Belohnungen: Rezept, Talisman, Kartenfragment). Das **ist** das Welt-Lore-System, ohne Textmauern.

### 8.10 **Die Stadt, die nach Steinen riecht** (Sinne)
- Geräusch: pro Bezirk eine eigene Klangtapete (Fuß: Wind in Leere; Staffeln: Hämmern; Stille: Glocken, Stille; Westmauer: Leerenatem).
- **Geruch-Hinweise im Text:** Hedda kocht Linsen, Tamsa riecht nach Ozon (Schleifstein), Perrin nach Wachs.
- **Foley** passend: Schritte klingen je nach Bezirk anders (Stufen hohl, Pflaster hell, Katakomben nass).

### 8.11 **Kinder und Katzen**
Kinderspiel auf der Treppe (Seilspringen am Brunnen, Murmeln, Verstecken), **Fundstücke** (Kieselglas, Federn, Knöpfe) als kleine Sammelstufen; die Katze Schiefer folgt Ellie ein Stück, wenn sie Fisch hat (Item, nicht gefangen, **kein Töten**). Keine kämpfenden Tiere, alle weich.

### 8.12 **Die Fernschau: Leerenfenster**
Nischen in der Westmauer, in die Ellie sich setzen kann. Sie sieht die Leere (Kamera lehnt leicht vor), hört Atmen, bekommt abhängig von Nacht/Mond **Visionen** (Teil der Story, nutzt `VoidEdge`-Shader-Zustände). Kein Kampf, nur Erzählung und Atmosphäre.

### 8.13 **Markttage und Feste**
- **Markttag** alle vier Tage (`TimeManager.day`): Stände, Karawane, Sonderwaren (Glasperlen, Samen, Leitstein-Splitter).
- **Lichterfest zum Vollmond** (`moon_phase` = 4): Laternen werden die Treppen hinabgetragen, Tanz am Forum, Gesang, Essen; die Stadt zeigt ihre ganze Pracht. Tagsüber vorbereiten (kleine Aufträge: Laternen malen, Brot backen, Girlanden binden).
- **Stein-Wettbewerb** (optional, Traum): Steinestapeln (Balance), Steinwurf (Weite), Quaderschieben (Kraft): einfache Minispiele ohne neue Kernsysteme.
- **Kartenspiel „Mauerspiel"** im Gasthaus (Traum): Steinplatten-Karten, hat Regeln, die Ellie lernt.

### 8.14 **Die Gerüste**
Immer irgendwo steht ein **Gerüst** (Holz, Seile, Körbe): Steinsetzer flicken Mauern, ein Turmdach, einen Torbogen. Fortschritt über Tage sichtbar; später ersetzt ein ganzes Stück „Alt" durch „Neu" (zeigt Stadtstufe). Verknüpfung: Ellie kann Material spenden (Stein, Holz) und beschleunigt den Fortschritt.

### 8.15 **Die Stadt, die zuhört (Nacht)**
Nachts ist Hallgrat **sicher in Licht**, aber die Leitsteine haben Grenzen (nutzt das System **Licht ist Land**). Ab Nacht 7+ prüfen Schatten (Nachtstufen: `lauschen`/`druck`/`flut`) die Mauer; ab Nacht 12 gibt es **Wallnächte**: Gegner sammeln sich am Tor, Ellie kann auf der Mauer helfen, Wachen geben Feuerschutz (Reuse `NightDirector.raids`, `story_hold`). Belohnungen: Ruf, Gegenstände. **Optional und spät.** Wichtig: **nichts wird der Stadt weggenommen** (Designregel aus Nachtkonzept).

### 8.16 **Die Antworten der Stadt auf Ellies Taten**
Reaktionssystem (klein, datengetrieben wie `Valdric chat`-Pools): Bewohner kommentieren Ellies Fortschritt (hat sie den Wegstein geweckt? den Leerenbrecher besiegt? ein Boss gefallen? ist sie verletzt?). Dialogpools pro Zustand; Dialogschreiber-Agent füllt Platzhalter.

### 8.17 **Stadtwappen und Banner**
Hallgrat bekommt ein Wappen (Kristall über zwei Mauerzinnen), das auf Wimpeln, Banner und Siegeln auftaucht und **bei Stadtstufe wechselt** (verblichen → leuchtend). Ellie bekommt am Ende ein Wimpel-Set für Glimmrast (Banner-Mechanik aus `A2 Stadtbanner`).

### 8.18 **Schmuck und Talismane in der Glasschleiferei**
Tamsa schleift **Kristalle für Talismane** (`glass_shard`, `leitstein_splitter`) und kann die **Ohrringe** aus `talisman_konzept` verfeinern; kooperiert mit Esma (Hexenwald): zwei Handwerkerinnen, zwei Stile (Hexen-grün vs. Kristall-türkis). Neue Talisman-Ideen: **Lauschstein** (Hörradius größer), **Echoanhänger** (Rückstoß-Schaden reflektiert), **Stillkranz** (Alarmradius kleiner).

### 8.19 **Pilgerweg und Wegsteinabkürzung**
Der **Westweg** hat ein Echo: ein **Rückwärts-Weg** („Pilgerpfad"), den Ellie später gehen kann, um Kleinigkeiten zu bringen (Karawanenaufträge) oder Wegsteine auf dem Weg zu aktivieren. Mit jedem aktivierten Leitstein am Weg sinkt die Reisezeit (Haltezeit der Wegstein-Reise).

### 8.19a **Die Stallungen (Reittiere, später)**
Der Stall im Fuß ist bewusst größer als alles andere im Fuß (16 × 9 Kacheln, Koppel 24 × 13). Er gehört zum Karrenhof, an dem der Westweg ankommt: Wer mit einem Tier kommt, stellt es hier ab. Eingeführt wird er um **Stufe 15 durch Jorun** (Hinweis im Gespräch, vielleicht ein Aushang); die Reittiere selbst, ihr Kauf, ihre Pflege und das Reiten sind ein **eigenes, noch nicht besprochenes System**. Im Grundriss ist der Platz reserviert (`stallungen` in data/hallgrat.json).

### 8.20 **Die Schwarze Mauer als Entscheidung**
Am Ende der Hauptquest kann Ellie die Schwarze Mauer **öffnen oder lassen** (siehe 12). Öffnen = neues Viertel, aber auch neue Gegner, Rückkehr der Toten (Gedenkmauer wird zu Tür), Lassen = sichere Stadt, aber verlorene Geschichte. Gleiche Frage wie bei der Ader.

---

## 9. Quests (Ideenliste, nicht ausgearbeitet)

### 9.1 Hauptstrang „Die Stille Stadt" (6 Schritte, Vorschlag)
1. **`west_road`** FOLGE DEM WESTWEG (Meilensteine, Raststationen, Vorboten).
2. **`west_gate`** BETRITT HALLGRAT (Brann, Rätsel, Einlass).
3. **`west_forum`** ERWECKE DEN WEGSTEIN (Ilvane, Welle, **Stadtstufe 1**).
4. **`west_voices`** DIE STIMMSTEINE (Perrin, 7 Steine, **Stufe 2**).
5. **`west_glass`** DER GLASBRUCH (Kristallmine, Herz der Ader, Entscheidung: reparieren oder abschalten).
6. **`west_wall`** DIE SCHWARZE MAUER (Corvin, Leerenbrecher-Hof, Entscheidung: öffnen oder lassen, **Stufe 4**).

### 9.2 Nebenquests (kurz, jede mit klarer Belohnung)
- **Der Lichtknecht:** Pim hat Angst vor der letzten Laterne (am Westrand). Ellie begleitet ihn. Belohnung: Laternenschlüssel.
- **Der Steinkopf:** Odriks Statue fehlt ein Stück; es liegt im Verlorenen Viertel. Belohnung: Steinbau-Rezept.
- **Die Briefträgerin:** ein Liebesbrief von der Oberstadt zum Fuß; Treppen, Katzen, Kinder.
- **Das verlorene Rezept:** Hedda braucht drei Zutaten für einen Eintopf der Vorfahren. Belohnung: Gericht im Küchenbuch.
- **Karawane in Not:** Jorun steckt am Westweg fest (Wagenpanne, Nacht); Ellie schützt sie. Belohnung: Handel.
- **Die Krähen auf dem Dach:** Ellie füttert Dachkrähen (Krähenmechanik existiert); bei Stufe 5 sammelt sich ein Schwarm am Mondturm.
- **Stille Nachtwache:** Ellie hält eine Nacht auf der Westmauer mit Wachen. Belohnung: Ruf, Gespräch, Blick.
- **Der Stimmer ohne Stimme:** Perrin hat seine Stimmgabel verloren (Zisterne, Rätsel).
- **Schleifstein:** Tamsa braucht einen reinen Kristall; Ellie sucht ihn im Glasbruch.
- **Kindersuche:** ein Kind versteckt sich in den Katakomben; Spiel, kein Horror.

### 9.3 Belohnungsarten (nichts, was neue Systeme erzwingt)
Rezepte, Bau-Unlocks (Stein), Talismane, Waffen-Skins, Karten-Reveals, Wegsteinabkürzungen, Hintergrundgeschichte, Gedenknischen, ein Sitzplatz am Mondturm, Stadtstufe.

---

## 10. Rätsel und Orte zum Herumprobieren (schnelle Highlights)

- **Das Fallgatter:** rostet seit 30 Jahren; Ellie kann es mit Öl (Fischöl, Tran von Maren) gängig machen; danach schließt es nachts (Atmosphäre).
- **Die Windmühle:** repariert sie, mahlt sie Mehl (Hedda backt Brot; Küche).
- **Die Wasserlinie:** in der Zisterne Hebel, die den Wasserstand ändern: erreichbare Türen und Schätze ändern sich.
- **Echo-Orgel:** Pfeifen in der Hüterhalle, auf die der Wind pfeift: eine Melodie, die Ellie nachspielen kann (E auf Pfeifen), öffnet eine Tür.
- **Die Treppe, die nie dieselbe ist:** eine lange Treppe mit versteckten Abzweigungen (Kinder zeigen sie). Technisch nur Interior/Overlay.
- **Wasserspeier-Zählung:** 24 Wasserspeier mit Gesichtern; einer blickt immer nach Westen. Wer ihn findet, bekommt Tamsas Dank.
- **Zeitreisende Schatten:** auf dem Forum liegt nachts ein Schatten der Wächterin, der um die Mutterstein-Statue wandert (Sonnenuhr-Effekt aus der Leere).

---

## 11. Gegner und Bedrohung (nur Bestehendes!)

- **Gebietsgegner:** Leerenbrecher (Glasklippen-Gegner), Spinnen, Horcher, Lichtfischer in der Zisterne (Wasser). Nichts Neues.
- **Schwarze Mauer:** keine Kreatur, ein **Hindernis** (Schattenfraß, `ShadowPatch`-Stil, `infest`-Look), das nur mit Quest/Licht verschwindet.
- **Wächter aus Stein** (Idee, nicht beschlossen): schlafende Statuen am Tor, die der Wegstein wachruft und die Stadt nur verteidigen (nie angreifen, sprachlos). Wäre ein neuer Gegner/NPC-Typ: **nur mit deiner Freigabe**.
- **Bosse:** keiner in Hallgrat selbst. Aber **Mornath** (Boss 1, (499, 258)) und **Morwenna** (Boss 2, Hexenwald) liegen weit; Corvin könnte Mornath-Rückblicke liefern (Hologramme, Rissfeder-Lore).

---

## 12. Entscheidungen für dich

**Beschlossen (2026-11-13):**
- **Standort:** A, der Glaskamm (Mitte etwa (150, 350), Wegstein *Wächterin des Glaskamms* (142, 355) wird das Forum).
- **Ton:** melancholisch-würdig.
- **Ader und Leere:** die Ader ist mit der Leere verwachsen (Entscheidung reparieren/abschalten bleibt für den Glasbruch).
- **Relief:** Stil-Rechteck um die Stadt (Mauerwerkwände, Treppen), nur Stil-Bytes, Test „Altland bytegleich".
- **Noch offen** (blockieren Stufe 1 nicht): Name (Arbeitsname Hallgrat bleibt bis dahin), Valdric/Corvin, Nachtsicherheit, Umzug, Zeitpunkt im Spiel, Größe der Besetzung.

1. **Standort:** A Glaskamm (empfohlen), B Klippenstock oder C Flachtal?
2. **Name:** Hallgrat, oder etwas anderes (Vorschläge: Klangfels, Schieferglocke, Mauerlicht, Altstein)?
3. **Ton:** eher **melancholisch-würdig** (Empfehlung, kontrastiert Glimmrast) oder **warm-lebendig**?
4. **Ader und Leere:** ist die Kristallader mit der Leere verwachsen (Vorschlag) oder sauberer Gegensatz?
5. **Valdric und die Rothalle:** darf Corvin Valdrics Orden und Gesicht berühren (große Story-Entscheidung), oder bleibt das für später?
6. **Wie sicher ist die Stadt nachts?** Ganz sicher (Licht ist Land), oder mit Wallnächten ab Stufe 12?
7. **Relief:** darf die Stadt-Umgebung ein Stil-Rechteck bekommen (Mauerwerk, Treppen) mit Test, dass alles andere bytegleich bleibt?
8. **Umzug:** darf ein Bewohner (Odrik oder Tamsa) später nach Glimmrast ziehen, oder bleibt Hallgrat in sich?
9. **Wann im Spiel?** Empfehlung: nach Boss 1, vor oder nach Hexenwald (Stufe 8–12), über **Story**, nicht über Entfernung (Schwierigkeit ist überall gleich).
10. **Wie groß soll die Besetzung sein?** 13 Personen sind viel Figurenarbeit; Kernbesetzung wären 6 (Brann, Ilvane, Odrik, Tamsa, Pim, Hedda), der Rest in späteren Stufen.

---

## 13. Technische Anbindung (Skizze, nichts davon gebaut)

Alles folgt den harten Regeln aus CLAUDE.md: **host-autoritativ, streng typisiert, Daten in JSON, Eingabe über `InputManager`**.

| Baustein | Idee |
|---|---|
| Daten | `data/hallgrat.json`: Bezirke, Gebäude, Plätze, Leitsteine (Position, Ton, Radius), Stadtstufen mit Bildzuständen, Tagespläne, Inschriften; `data/dialogue.json`, `data/shops.json` (Steinmetz, Glasschleiferei, Wirtin, Karawane), `data/recipes.json` (`unlocks: "stone"`) |
| Welt | `ground.json` Eintrag `towns[]`: Anker, Stil-Rechteck, Gebäude (Hut-artige Pieces mit `LOOKS`), Plätze/Pflaster als gebackene Bodenbilder (`bake_ground.py --yards`, neue `palette: "town_stone"`) |
| Streaming | Hallgrat ist ≈ 5 Chunks groß; Gebäude als `HutYard`-artige Sprites je Chunk, Bodenbilder als Decals; **Backen im Voraus, Anwenden im Hauptthread** (Jobs-Regel). Ein `HallgratDirector` (Node von `WorldLevel`) hält Zustand und Ereignisse |
| Innenräume | `Interiors`-Slots pro Haus (`data/interiors.json`, Einträge in `Doorway`, Art-Skript je Raum nach `art_hut`-Muster; runde Räume wie `witch_room` für Mondturm und Zisterne) |
| Bewohner | `Settler`-Pläne (`settlers.json`), `InteriorResident` für Innenpersonen, `away`-Flag für Handelspartner; **Figuren und Texte von den eigenen Agenten** |
| Läden | `ShopWindow` / `BoardWindow`, `TownManager.register_person/outpost` |
| Licht | Leitsteine als feste Lichtkreise in einer neuen Quelle neben `TownManager.circles()` (`WorldLights`), damit `light_depth` / `spawn_blocked` / `NightDirector` sie kennen |
| Wegstein | Existiert (`WaystoneStatue`, `Waystones`, `begin_touch`, Welle); Erweiterung nur durch Leitstein-Welle (Signal an `HallgratDirector`) |
| Stadtstufen | Zustand als gespeichertes Dictionary (`save key "hallgrat"`), Replikation per `_rpc_state` + Snapshot für Joiner |
| Karte | Marker + Gebietsname + Entdeckung (vorhanden), Leitstein-Symbole auf der Karte |
| Wetter | `exposure_at`, Rinnen und Spritzer als Detail-Pass (Daten in `weather.json` Region Glasklippen) |
| Audio | `py -3 tools/audio_hallgrat.py` (Glocke, Schleifstein, Hammer, Klangmotiv, Halleffekt-Zonen) |
| Art | `tools/art_hallgrat_*.py` (Terra-Agent) + Stein-Bake `tools/bake_hallgrat_relief.py` (nur Stil-Bytes im Stadt-Rechteck, Test gegen Altland) |
| Tests | `tools/test_hallgrat.tscn` (Layout-Prüfung: Wege frei, Türen erreichbar, keine Props in Häusern, alle Tore passierbar, Stadtstufen-Zustände, Save/Load, Mehrspieler-Snapshot), `tools/preview_hallgrat.tscn -- --capture=…` pro Bezirk, Tag und Nacht |

**Risiken** (ehrlich):
- **Staffeln und Sortierung:** In einer Terrassenstadt liegen Dächer „über" Gassen; Y-Sort ist 2D-3/4. Lösung: konsequent **Wände als Relief-Wände** (schon geschützt), Gebäude als Props mit klarer Standlinie, **Torbögen** als Props mit Kronen-Ausblendung (wie Bäume, `FirTree._covers`). Echte Brücken *über* Gassen vermeiden oder nur als Deko.
- **Prop-Last:** ein Dutzend Pflanzenarten, viele Wasserspeier und Lampen: pro Chunk zählen, Backen statt Laufzeit.
- **Relief-Ausnahme:** `Relief._apply_world_biome` müsste ein Stil-Rechteck kennen. Kleine Änderung, aber an der Stelle, die die ganze Welt prägt: erst Test, dann bauen.
- **Weg und Wegstein-Wetter:** der gebackene Westweg muss auf flachem Ebene-0-Land bleiben (Regel im Fußpfad-Abschnitt).
- **Mehrspieler:** Stadtstufe und Wellenszene brauchen Host-Entscheidung und Replikation; Szenen (Erweckung) laufen wie bisher solo/host und werden für Co-op später verallgemeinert.

---

## 14. Stufenplan (kleine, einzeln abnehmbare Schritte)

| Stufe | Inhalt | Ergebnis |
|---|---|---|
| **0** | Dieses Konzept gemeinsam aussortieren (Abschnitt 12) | Entscheidungen, Namen, Ton |
| **1** | **Grundriss:** `data/hallgrat.json`, Skizze der Bezirke auf dem echten Relief (Kachelraster-Vorschau), Westweg bauen (`paths`), Meilensteine | Man läuft hin, sieht die Stadt als Umriss |
| **2** | **Stein-Umdeutung:** Stil-Rechteck, Mauerwerkwände, Treppen, Test „Altland bytegleich" | Das Gelände *sieht* nach Stadt aus |
| **3** | **Außenhülle:** Tore, Mauern, Pflaster, Plätze, ca. 20 Häuser als Fassaden (Terra-Art), Licht, Wetter, Klang | Man kann durchgehen, es fühlt sich wie Stadt an (noch leer) |
| **4** | **Wegstein-Erweckung** + Stadtstufen 0→1 (die große Szene) | Wow-Moment |
| **5** | **Kernbesetzung** (6 Figuren) + Tagespläne + Gasthaus, Steinmetz, Glasschleiferei als Innenräume + erste Shops | Die Stadt lebt, man kann handeln |
| **6** | **Quest-Strang 1–4** (Westweg, Tor, Erwecken, Stimmsteine) + Inschriften | Spielbarer Bogen |
| **7** | **Untergrund:** Zisterne, Katakomben, Glasbruch (Mine-Zone) | Dungeon-Anteil |
| **8** | **Schwarze Mauer + Verlorenes Viertel** + Finale + Stadtstufe 4 | Story-Abschluss |
| **9** | **Feste, Markttage, Nachtwache, Karawane, Gedenkmauer, Mondturm-Vorhersage** | Langzeit-Lebendigkeit |

Jede Stufe endet mit Test, Vorschau-Capture (Tag und Nacht), Doku-Eintrag in CLAUDE.md und einem Check-in mit dir.

---

### 14.1 Stand Stufe 1 (gebaut 2026-11-13)

**Grundriss** in `data/hallgrat.json` (Kacheln): sechs Bezirke als Polygone auf dem echten Relief, 25 Orte mit Ebene und Bezirk, fünf Wege, drei Tore, 16 Leitsteine mit ihrem Ton (0–3 des Stadtmotivs), der Stil-Bereich für Stufe 2. `py -3 tools/preview_hallgrat_plan.py [--fix]` prüft den Plan gegen das Relief (jeder Ort steht auf seiner Ebene, jeder Weg wechselt die Ebene nur über einen Verbinder) und zeichnet `docs/img/hallgrat_plan.png`; `--fix` routet die Wege über ihre `via`-Punkte und rückt Orte zurecht, die nicht passen.

Was das Gelände vorgibt (anders als im ersten Entwurf gedacht):
- Vom Vorland kommt man nur über die **Felsstufen bei (186, 342)** auf den Gipfelrücken: Das ist das **Osttor**. Die Rampe bei (179, 371) führt nicht vom Vorland herauf, sondern von der Torgasse (Ebene 1) in die Staffeln (Ebene 2).
- Die Hauptachse **„Die Steige"** läuft fast gerade nach Westen hinauf: Torstraße → Markt → Osttor → Torgasse → Torstufen (178, 355) → Werkgasse → Forumstufen (164, 354) → Forum um die Wächterin (142, 355).
- Die Westmauer steht auf dem äußeren Ring (Ebene 1, x 111–115). Zu ihr steigt man vom Gipfel über den Westring (Ebene 2) hinab und geht an dessen Nordende über die Stufen (120, 329) auf den Wehrgang.
- Der Mund des Glasbruchs liegt in der Senke nördlich des Gipfels (Ebene 0). Die Brunnenmulde ist eine Senke auf Ebene 1 im Süden der Staffeln.

**Der Westweg**: `py -3 tools/bake_westweg.py` sucht die Trasse über das gebackene Gelände. Er zweigt bei (793, 573) von Joruns Karrenweg nördlich von Glimmrast ab und führt rund 790 Kacheln über flaches Land der Ebene 0 zwischen den Seen hindurch bis vor das Osttor. Er hält Abstand zu Klippen, Wasser, dem Einführungs-Korridor und allen handgesetzten Orten. Er ist eine **alte Straße**:
- Unterwegs sind nur Reste der Pflasterung zu sehen.
- Im letzten Drittel wird sie ganz gepflastert und bekommt Randsteine (`old_road` in `tools/bake_ground.py`).
- Sie ist in 11 Stücke gebacken (`arc`, gemeinsames `seed`, in der Welt verankertes Rauschen), die ohne Naht aneinanderstoßen: `py -3 tools/bake_ground.py --path=westweg`.

**Meilensteine** alle 50 Kacheln Weg (15 Stück, 750 bis 50):
- Sie stehen am Wegrand (`Milestone`, Bilder von `py -3 tools/art_milestone.py`).
- Fern der Stadt sind sie alt, schief und bemoost, ihr Kristall ist tot. Von 150 an glimmt er violett, beim letzten Stein (50) flackert er nachts türkis.
- E liest die Inschrift und einen Gedanken von Ellie (Platzhalter, `milestone_text`). Dazu klingt der Ton des Steins aus dem Stadtmotiv (`py -3 tools/audio_hallgrat.py`).

**In der Welt**:
- Der Knoten `Hallgrat` stellt die Meilensteine auf und markiert die Stadt auf der Karte (Marker `hallgrat`, sobald das Forum gesehen wurde).
- Er zeichnet für Entwickler den Plan auf den Boden: ENTWICKLER → HALLGRAT: PLAN ZEIGEN / ZUM OSTTOR / WESTWEG: ZUR GABELUNG.
- Test: `tools/test_hallgrat.tscn` (74 Prüfungen, `HALLGRAT OK`). Mit `--rendering-driver opengl3 ... -- --dir=/abs` macht er dieselben Bilder: Gabelung, Weg, letzter Stein bei Nacht, Tor und Forum mit Plan.

Noch nicht gebaut: Stil-Bereich (Stufe 2), Häuser, Mauern, Pflaster, Menschen; ein Wegweiser an der Gabelung; die Leitsteine am Weg (Vorboten ab Meile 150) als eigene Objekte.

### 14.2 Stand Stufe 2 (gebaut 2026-11-14)

**Stein statt Fels:**
- Die Stadt bekommt ihr Aussehen beim Laden: `Relief._apply_town_styles` färbt nach `style_areas` in data/hallgrat.json die Kacheln ganzer Bezirke um. Das geschieht nach dem gemeinsamen Wiesen-Look.
- `relief.png` wird **nicht neu gebacken**. Es ändern sich nur das Stil-Nibble und bei Mauerwerk die Art der Felsstufen (STEPS → STAIRS).
- Höhen, Verbinder-Geometrie, Feld und Kollision bleiben so, wie sie gebacken sind. Beide Arten sind für jede Abfrage Verbinder (Höhe, Schritte „stone“, Kollision).

**Die Bezirke:**
- **Mauerwerk (2)** in der Stille, den Staffeln, der Randpromenade und dem Fuß. Die Terrassenwände werden Stützmauern aus Quadern, die Felsstufen gehauene Treppen mit Wangen (`relief.gdshader`: Mauerwerk-Treppen nutzen die steinerne `steps()`, nicht die grasigen `forest_steps()`).
- **Kristall (3)** am Glasbruch: violette Adern, die nachts leuchten.
- **Leere (4)** im Verlorenen Viertel.

**Prüfung:** `tools/test_hallgrat.tscn` (jetzt 87 Prüfungen) vergleicht das Relief mit und ohne Stadtstil (`Relief.town_styles`):
- Außerhalb der Bezirke ist jedes Byte gleich.
- Kein Höhen-, Geometrie- oder Biom-Byte bewegt sich.
- Nur Felsstufen werden zu Treppen.
- Die Kollision ist die gebackene.

`tools/test_shared_biome.tscn` prüft die Wiesen-Regel jetzt ohne die Stadtausnahme.

**Grenze des Bilds:** Hohe Mauern zeigt das Relief nur an Südkanten. Ost- und Westränder sind schmale Kanten, die Westmauer sieht man darum erst mit den Mauer-Bauwerken aus Stufe 3. Das Verlorene Viertel zeigt die Leere nur an seinen Rändern, die Schwarze Mauer kommt in Stufe 8.

### 14.3 Stufe 3 in drei Teilen, Stand 3a (gebaut 2026-11-14)

Stufe 3 (Außenhülle) ist geteilt:
- **3a Boden:** Plätze und Gassen. Gebaut.
- **3b Häuser:** Steinhäuser als Fassaden mit Fensterlicht und Rauch.
- **3c Mauern und Tore:** Westmauer mit Zinnen, Torhäuser, Leitsteine als leuchtende Objekte, Klang.

**3a, der Boden:** `py -3 tools/bake_hallgrat_ground.py` legt die Flächen aus `paving` in data/hallgrat.json. Gepflastert wird nur auf dem Boden der eigenen Ebene, ein paar Pixel vor jeder Kante; Treppen und Rampen zeichnet das Relief.
- **Forum (`ring`):** Ringpflaster in elliptischen Lagen um die Wächterin, jede vierte Lage dunkler, Randsteine am Saum. Ihr Steinbett bleibt frei.
- **Brunnenhof:** kleiner Ring.
- **Gassen (`setts`):** Steige, Karrenrampe, Mauerweg und Muldenstiege als gesetzte Steine im Verband mit Randsteinen. Die Linie folgt dem gerouteten Weg ohne Kachelstufen (Douglas-Peucker, dann Catmull).
- **Alte Platten (`flags`):** Nordgasse, Steinmarkt und Karrenhof.
- **Abnutzung (`wear`):** Sie nimmt Steine weg, lässt Gras in die Fugen und Moos auf die Steine und franst den Rand aus. Die Stille ist gepflegt, der Fuß halb verlassen.

**Nach dem ersten Ansehen überarbeitet (2026-11-14):**
- **Die Wächterin steht auf festem Grund.** Das Forum hat ein Podest (`dais`) aus großen Keilplatten mit einer niedrigen Stufe aus langen, dunklen Randsteinen, und ihr wildes Graspflaster ist ausgeblendet (`paved` in data/waystones.json, `WaystoneStatue.paved`). Das Leuchten ihrer Linien bleibt.
- **Gassen weniger perfekt:**
  - Die Steinreihen liegen quer zur Gasse in ihrem eigenen Verlauf statt am Weltraster. Die Steine sind 8 bis 12 px lang, manchmal zwei zu einem verschmolzen, die Reihen wackeln leicht.
  - Jeder Stein hat einen eigenen Ton. Licht und Schatten an den Kanten kommen aus der Welt (von links oben), egal wie die Gasse läuft.
  - Dazu gesunkene Steine, Risse, Fugen aus Mörtel, Erde oder Gras, eine in der Mitte glattgelaufene Spur und Randsteine.
- **Passend zu den Treppen:**
  - Das Pflaster läuft bis an die erste und letzte Stufe heran, ohne Grasstreifen. Vor jeder Treppe liegt eine Reihe breiter Absatzplatten parallel zu den Stufen.
  - Gassen, Treppen und Mauern teilen jetzt denselben Stein (die MASON-Palette des Relief-Shaders).
- **Treppen detaillierter** (`mason_stairs` in relief.gdshader):
  - Stufen aus Platten verschiedener Länge mit heller Kante und dunkler Setzstufe, in der Mitte heller abgetreten.
  - Abgeschlagene Kanten, einzelne Risse, Wangenmauern mit Decksteinen, Moos und Gras in Ecken und Fugen.

Die Flächen kommen als Decals `hallgrat_<id>` (Oberfläche `stone`) in ground_baked.json. Die gepflasterten Kacheln stehen in `hallgrat_clear`; `WorldLevel` hält sie frei von erzeugten Pflanzen und Steinen. Test: `tools/test_hallgrat.tscn` (91 Prüfungen).

### 14.4 Stand 3b: Häuser, Stall und der Markt um die Wächterin (2026-11-14)

**Die Bilder:** `py -3 tools/art_hallgrat_houses.py [preview.png]` baut die Gebäude aus Ellipsoiden wie die Schmiede.
- **Material:** Quader im Verband mit Ecksteinen und Sockel, Stürze und Bänke aus hellem Stein, Rundbogentüren, Fensterläden im staubigen Blau der Stadt, Schieferdächer in kalten Tönen, Schornsteine.
- **Typen:**
  - Wohnhäuser `haus_a`/`haus_b`/`haus_hoch`, dazu `giebel` und `laden` (Werkstatt mit türkisem Tuchvordach)
  - verlassene Häuser `verlassen_a`/`_b` mit vernagelten Fenstern, Moos und Efeu
  - `halle` mit türkiser Rosette und Strebepfeilern, `torhaus` mit Zinnen und Schießscharte
  - **`stall`** (die Stallungen): lang, großes Doppeltor, Heuboden mit Lastbalken, kleine hohe Fenster
- **Tiefe** (nach dem ersten Ansehen):
  - Jedes Haus ist leicht gedreht, sodass eine Seitenwand im Schatten zu sehen ist.
  - Die Traufe springt weit vor, mit dunklem Traufbrett, Sparrenköpfen und Ortgang.
  - Unter jedem Dach und Tuch liegt ein gerasterter Schlagschatten auf der Wand (`eave_shadow`).
- **Nacht:** Das Fensterglas leuchtet auf einem eigenen, unbeleuchteten Bild.
- **Daten:** Größe, Fußpunkt, Grundfläche und Lichter stehen in data/hallgrat_art.json.

**Der Markt um die Wächterin** (Wunsch 2026-11-14):
- Zehn Marktstände stehen im Ring ums Forum (`forum_market` in data/hallgrat.json: Radius, Winkel). Jeder ist zur Statue gedreht, die Steige nach Osten und Westen bleibt frei.
- Die Stände haben drei Tuchfarben mit eigener Ware: Türkis/Leinen mit Äpfeln und Rüben, Weinrot/Ocker mit Krügen und Kristallen, Violett/Leinen mit Stoffballen und Kräutern.
- Jeder Stand gibt es von vorn, von hinten und von der Seite (die andere Seite gespiegelt). Das Dach ist ein durchhängendes, gewölbtes Tuch auf einem Firstbalken, mit Saum.

**Platzierung (zweimal nach Kritik überarbeitet, 2026-11-14):**

`py -3 tools/place_hallgrat_buildings.py` arbeitet nach drei Regeln:
1. **Jede Tür ist sichtbar und führt auf einen Weg.** Häuser zeigen immer ihre Front mit dem Eingang (Ansicht `s`). Jede Tür bekommt einen kleinen gesetzten Steinweg zur nächsten Gasse. Der Weg wird per A* über den freien Boden der eigenen Ebene gesucht und von `bake_hallgrat_ground.py` als `hallgrat_zugang_<n>` gebacken. Ein Haus ohne möglichen Weg wird weggelassen.
2. **Kein Haus steht vor einem anderen.** Vor jeder Tür bleibt ein Streifen von 60 px frei, so hoch steigt ein Dach über seine Grundfläche.
3. **Häuser nur in den Bezirken der Stadt.** In Stille, Staffeln und Fuß wachsen außerdem keine erzeugten Bäume oder Büsche.

**Ablauf:**
- Zuerst kommen die benannten Gebäude aus `buildings`, dann die Häuserreihen an den Gassen (`rows`), dann die Füllung der Terrassen von hinten nach vorn (`fill`, je Bezirk und Ebene).
- Danach kommen die Wege von den Türen, zum Schluss der Markt eng um die Wächterin.
- Das Ergebnis landet in `placed` und `door_paths`.

**Reihenfolge der Werkzeuge:** `bake_hallgrat_ground.py` (Gassen) → `place_hallgrat_buildings.py` → `bake_hallgrat_ground.py` (jetzt mit den Türwegen). `hallgrat_streets` hält die Gassen ohne die Türwege.

**Im Spiel:**
- `HallgratBuilding` zeichnet ein Gebäude: Sortierung an der Vorderkante, Leuchten nachts, Kollision auf der Grundfläche.
- Steht der Spieler dahinter, blendet es halb aus wie eine Baumkrone.
- `Hallgrat` hält den Boden darunter frei von erzeugten Pflanzen.

### 14.5 Stand 3c: Westmauer, Leitsteine, Glocke (2026-11-14)
- **Westmauer** (`walls` in data/hallgrat.json): Eine Brustwehr aus Quadern mit Wehrgang und Zinnen zur Leere hin. Sie läuft in 16-px-Stücken (`mauer_ns`) auf dem Außenring von (110.7, 334) bis (110.7, 364).
- **Leitsteine** (`HallgratLeitstein`):
  - schlanke sechseckige Pfosten mit eisernen Bändern und einem Klangstein-Kristall im Kopf (Bilder `leitstein`/`leitstein_wach`/`leitstein_tot`)
  - Die Stadt schläft noch, darum erinnert sich der Kristall nur schwach violett an sein Licht, nachts kommt und geht es. Der Stein im Verlorenen Viertel ist tot.
  - E „ANSCHLAGEN“: Der Stein klingt in seinem Ton (0–3) des Stadtmotivs, und der Kristall flammt kurz auf. Das ist die Vorbereitung für die Stimmsteine (8.1) und das Erwachen (Stufe 4).
- **Glocke:** Zur Dämmerung (Uhrzeit 0.79) schlägt die Glocke im Mondturm dreimal, `glocke.wav` aus `py -3 tools/audio_hallgrat.py`, in der Stadt weit zu hören.
- **Rothalle:** Sie hat ihren Platz nördlich der Hüterhalle, die benannten Gebäude suchen weiter (`reach`) und halten auch ihre Tür frei.
- **Noch nicht gebaut:** Wachposten auf der Mauer, die Schwarze Mauer als Objekt, Gassenklang je Bezirk, Lichtrunde.

### 14.6 Überarbeitung der Häuser (2026-11-14)
- **Stein wie der Boden:**
  - Die Mauern sind in denselben Steinen geschnitten wie Gassen, Treppen und Terrassenmauern (MASON-Palette).
  - `wall_pass` legt sie als Lagen von Quadern: 5 px hoch, 7 bis 12 px lang, versetzt, mit dunklen Fugen, heller Ober- und Linkskante und eigenem Ton je Stein. Das Licht der Form bleibt.
  - Das Schiefer ist ins Violett der Wände gezogen.
- **Vordach:** Über jeder Haustür hängt ein kleines Schieferdach auf Eisenkonsolen, mit Stufe davor.
- **Seitlich gedreht an Nord-Süd-Wegen** (Ansicht `e`/`w`): Die Tür zeigt zum Weg, ihr Türweg beginnt an dieser Seite. Zwischen solchen Häusern bleibt so viel Abstand, wie ihr Bild höher als ihr Fuß ist, damit kein Dach das nächste verdeckt.
- **Maßstab nach Ellie** (52 px, Tür ≈ 40 px):
  - Die Modelle werden je Art vergrößert: Häuser ×1,9, Hallen ×1,6, Torhaus ×1,7, Stallungen ×1,3, Mauer ×1,6, Leitsteine ×1,5, Stände ×1,6 (`GROW`).
  - Die Steinlagen bleiben gleich groß. Damit stehen jetzt rund 40 Häuser und Hallen und 8 Stände.
- **Diagonal an schrägen Wegen** (Ansichten `se`/`ne`, im Spiel gespiegelt `sw`/`nw`):
  - Wohnhäuser (`DIAG_TYPES`) werden zusätzlich um 48° gedreht gerendert, so dass Front und Seite beide zu sehen sind. Die rechnerisch exakte Drehung für einen 45°-Weg (`atan(1 / SINP)`) versteckte die Tür fast ganz.
  - `hallgrat_art.json` speichert dazu `door` (Tür relativ zu den Füßen) und `poly` (die gedrehte Grundfläche).
  - Der Platzierer wählt diagonal, wenn die Wegnormale schräg liegt (beide Anteile > 0,42). Er setzt die Tür auf den Wegrand, prüft und belegt die Kacheln unter dem Polygon und hält eine Türschwelle auf dem Weg frei. Rückansichten (`ne`/`nw`) sind wie `n` nicht in den Standard-`views` einer Reihe.
  - `HallgratBuilding` bekommt dann ein Kollisionspolygon statt eines Rechtecks. Erste Anwendung: das Westweg-Ende vor dem Osttor (5 Häuser).
- **Fensterlicht:** Lampenlicht hinter Glas in einem ruhigen Honigton (`GLASS`, 4 Stufen), statt der flackernden Feuer-Rampe, die wie Flammen in den Fenstern aussah. Oberste Reihe und Seiten liegen eine Stufe dunkler, manche Fenster brennen schwächer.
- **Plätze im Gassenpflaster:** Steinmarkt, Karrenhof und Nordgasse sind jetzt `setts` statt `flags`. Ein Platz (`poly`) bekommt `paint_square`: dieselben Steinreihen wie die Gassen (Ost-West), einen Rand aus langen Steinen und weniger Abnutzung (`wear` 0,22 / 0,3).
- **Offen:** Die Rothalle findet in der neuen Größe keinen Platz. Sie braucht einen eigenen Ort (zum Beispiel die Brunnenmulde) oder eine schmalere Form.

## 15. Ideenspeicher (alles, was noch nirgends hineinpasste)

- Eine **Sonnenuhr** am Forum, deren Schatten die Mondphase *und* die Stadtstufe anzeigt.
- **Handwerksmarken:** jedes Haus trägt ein Meisterzeichen; Ellie sammelt sie (Inschriftenbuch).
- **Der Bettler am Tor**, der immer dieselbe Geschichte erzählt (jede Version ein bisschen anders: wer lügt?).
- **Ein Friseur in der Staffel**, der Ellies Haare nur kosmetisch frisiert (Hair ist nicht änderbar: nur Schleife/Band als kleine Stoff-Anbindung, Charakterdesign beachten).
- **Zwei Leitsteine, die sich streiten:** ein flackerndes Paar, bei dem man den Ton erst angleichen muss (Mini-Rätsel).
- **Ein Wasserspeier, der nachts leise summt** (Wind in einer Kehle).
- **Der Turmwächter-Hund-Gleichnis:** eine Statue eines Hundes am Tor; Kinder legen Blumen davor (Gedenken ohne Tote).
- **Schrägstufe-Stille:** eine Stufe, die niemals Geräusche macht (Geheimtür dahinter).
- **Blumen in Mauerfugen**, die tagsüber blühen und nachts glimmen (Flora-Reuse: `moonbell`, `mist lily`).
- **Eine Bibliothekskatze** (Schiefers Cousine) im Archiv, die bestimmte Bücher umwirft; Hinweise.
- **Alte Stadtpläne**, die nicht mit der Stadt übereinstimmen (die Stadt hat sich verändert: Hinweise auf Geheimgänge).
- **Der Glockenschlag** schlägt je nach Stadtstufe ein anderes Motiv; bei Stufe 4 klingt er wie die Wegsteinwelle.
- **Echo-Ellie:** auf der Westmauer antwortet die Leere mit ihrer eigenen, leicht verzerrten Stimme (Stimmenüberlagerung): eine Warnung oder ein Versprechen (Story-Haken für Boss-Zwischenspiele).
- **Pilze im Keller:** Glimmkappen als Handwerkslicht, Hedda zieht sie im Keller.
- **Gerüchte-System light:** jede Figur kennt drei Gerüchte; Ellie sammelt sie als Zettel, die auf der Karte kleine Fragezeichen setzen (Hinweise zu Dungeon, Schätzen, Bossen).

---

*Nächster Schritt: Abschnitt 12 durchgehen (Standort, Name, Ton, Ader/Leere, Valdric-Haken). Danach schreibe ich den Grundriss (Stufe 1) als konkrete Kachelkarte mit Vorschau auf dem echten Relief.*
