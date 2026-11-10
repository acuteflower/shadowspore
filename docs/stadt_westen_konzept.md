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
