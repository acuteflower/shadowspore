# Beutetruhen (Konzept und Stand, 2026-11-11)

Truhen in der Wildnis: etwas, das man **findet**, nicht kauft. Später liegen sie hinter Rätseln, an schwer erreichbaren Orten, in Schluchten, auf Plateaus ohne Rampe, hinter Dornen, unter Wasserfällen. Dieser Schritt baut **das System, die Art und die Öffnungen** – es wird **noch keine Truhe in die Welt gelegt** (`placed` in `data/loot_chests.json` ist leer, nur der Entwickler-Knopf stellt Testtruhen hin).

## 1. Die drei Truhen

| Stufe | Name | Idee | Licht | Öffnen |
|---|---|---|---|---|
| Gewöhnlich | **Wurzelkiste** | Die Kiste eines Wanderers, die der Wald zurückgeholt hat: verwittertes Pflaumenholz, rostige Bänder, ein Vorhängeschloss, Moos, eine Wurzel, die sich über die Ecke krallt, ein Teal-Pilz am Kufenholz. | Kaum: der Pilz und ein silbriger Schimmer aus dem Spalt. | E antippen: Ellie bückt sich, das Schloss springt ab, der Deckel knarrt hoch, Staub, Samenflocken. |
| Selten | **Mondsiegeltruhe** | Schieferblaues Eisenholz, blauer Stahl, Klauenfüße, eine Mondsichel auf dem Deckel. Vorn ein **Siegel aus Mondstein**, an der hinteren Ecke wachsen Mondkristalle aus dem Boden. Innen violetter Samt. | Kaltes Blau (`#5aa8ff`): Siegel, Runen, Kristalle; nachts ein blauer Lichtsee. | **E halten (0,9 s): SIEGEL BRECHEN.** Ein Runenring auf dem Boden füllt sich, das Siegel brummt und flackert. Dann zerspringt es in Splitter, der Deckel fliegt auf, ein Fächer aus blauen Strahlen steigt, Mondfunken spiralen hoch. |
| Legendär | **Glutreliquiar** | Ein Reliquienschrein auf einem Steinsockel: schwarzer Lack, Goldfiligran, Flügelbeschläge, ein **Sonnenherz aus Bernstein** im Deckel, zwei Kerzen. Die Leere hat es **mit schwarzen Ketten gefesselt** (violette Adern), und schwarze Adern kriechen über den Sockel. Innen der Weinrot-Samt von Valdrics Orden und Gold. | Bernstein-Gold (`#ffb347`), Kerzen, die Kettenadern violett. | **E halten (1,6 s): FESSELN LÖSEN.** Die Ketten glühen von Violett zu Gold, klirren, der Boden-Runenkreis zieht sich zu. Dann reißen die Ketten (Glieder fliegen), eine halbe Sekunde Stille, das Sonnenherz blendet auf – der Deckel sprengt auf, eine **Lichtsäule**, ein Schockring, Münzfontäne, Kameraschütteln; die Beute springt eine nach der anderen hoch heraus, **das Beste zuletzt**. |

Gemeinsame Regeln fürs Aussehen (design_guide): von oben links beleuchtet, Tinte als Kontur, nur die leuchtenden Pixel liegen auf der unbeleuchteten Glow-Ebene (am Tag gedämpft, nachts voll). Die Leere ist Violett/Schwarz, Schattenwesen-Magenta bleibt den Kreaturen vorbehalten.

## 2. Beute

- Daten in `data/loot_chests.json`: `pools` (gewichtete Einträge `{id, w, n: [min, max]}`) und `tiers` mit `draws` (`{pool, count: [min, max], chance}`), Kupfer, XP, Haltezeit, Teilungsradius.
- `LootRules.roll` (rein, getestet): pro Ziehung ohne Zurücklegen, gleiche Items werden zusammengelegt, **sortiert nach Seltenheit aufsteigend** – so springt das Beste zuletzt heraus.
- Gewöhnlich: Wildkräuter, Beeren, Erz, Seil, kleine Tränke, ab und zu eine Stufe-1-Gemme oder ein Barren.
- Selten: garantiert ein seltener Fund (Kristall/Gemme Stufe 3, Trank Stufe 4, `wuchtreif`), dazu ungewöhnliches Material.
- Legendär: garantiert ein epischer Fund (Stufe 4), 35 % Chance auf einen legendären (Kristall/Gemme Stufe 5, `schweigtropfen`), dazu seltenes Material. Boss-Reliquien (`rissfeder`), Quest-Material (`mora_shard`) und geschmiedete Waffen sind nie in Truhen.
- Kupfer und XP bekommt **jeder lebende Spieler im Umkreis** (`share_radius`), Items fallen auf den Boden; pro weiterem Spieler in der Nähe eine Ziehung mehr (`per_player`). Truhenbeute liegt 5 Minuten (`ItemDrop.life`).

## 3. System (gebaut)

- `LootChests` (Knoten von `WorldLevel`, Gruppe `loot_chests`): **host-autoritativ**. `request_open(id)` -> Host prüft Reichweite, Leben, Zustand -> `_rpc_opened` spielt auf jedem Peer die Öffnung, der Host zahlt im Takt der Animation (`burst` aus `data/loot_chest_art.json`) und lässt die Beute gestaffelt herausspringen (`ItemDrop.rise/pop`). Snapshot für Nachzügler, Speicherstand `"chests"` (geöffnete Ids). `place(id, tier, pos, flip)` ist die Schnittstelle für spätere Orte/Rätsel; `placed` in der JSON wird beim Start gelegt (leer).
- `LootChest` (`Interactable`): Sprite-Sheet mit 9 Spalten (0 verschlossen, 1 entriegelt, 2-8 Deckelwinkel), Glow-Sheet, `NightLight`, Kollision, Halten von E (`InputManager.interact_held`), Ellies Bück-Animation (`Player.begin_pick`), alle Effekte als Pixel (`_draw` auf einer unbeleuchteten Ebene): Boden-Siegel, Halte-Ring, Strahlen, Lichtsäule, Schockring, Splitter, Kettenglieder, Münzen, Funken.
- Art: `py -3 tools/art_loot_chests.py [preview.png]` (eigener Box-Raytracer + die Ellipsoide von `art_hero3d`: echte Planken mit Maserung, Fasen, Fugen) -> `assets/props/chests/chest_{common,rare,legendary}{,_glow}.png` + `data/loot_chest_art.json` (Rahmen, Bodenzeile, Ankerpunkte). Töne: `py -3 tools/audio_loot_chests.py` -> `assets/audio/chest/`.
- Entwickler: Pause -> ENTWICKLER -> TRUHE: GEWÖHNLICH / SELTEN / LEGENDÄR stellt eine Testtruhe vor Ellie (nicht gespeichert).
- Test `tools/test_loot_chests.tscn` (druckt `LOOT CHESTS OK`), Ansicht `tools/preview_loot_chests.tscn -- --capture=/abs.png [--night] [--t=sekunden]`.

## 3a. Boss-Truhen (gebaut)

- Ein Gegner, dessen `loot`-Block in `data/enemies.json` einen `chest`-Block hat (`{tier, delay, bonus: [draws]}`), verstreut nichts mehr: `DropComponent._to_chest` würfelt seine Items wie bisher (`roll_entries`) plus die `bonus`-Ziehungen aus den Truhen-Pools und übergibt alles mit Kupfer, XP, Gewinnern (Peer-Ids) und Reliquien an `LootChests.boss_chest`.
- Nach `delay` (2,8 s, die Todesanimation darf wirken) stürzt ein **Glutreliquiar in einer Lichtsäule vom Himmel**, schlägt mit Schockring, Staub und Kameraschütteln auf (`LootChest.arrive`, `descend` + `boom`). Mornath landet südlich des Sonnensiegels (`SkyCleaver.chest_spot`, das Hologramm bleibt frei), Morwenna dort, wo sie fällt.
- Öffnen wie jedes Reliquiar (Ketten lösen). Kupfer/XP gehen an **dieselben Gewinner** wie vorher (auch wenn sie inzwischen tot sind), die Items springen heraus, die Reliquie (`BossRelics.roll`: Rissfeder, Mora-Splitter) kommt als Letztes, nur für ihren Besitzer. Der Kill zählt für die Reliquien-Statistik beim Öffnen.
- Ungeöffnete Boss-Truhen stehen im Speicherstand (`chests.boss`: Ort + Inhalt); geöffnete Boss- und Testtruhen verblassen nach `fade_after` (45 s). Ein Rückkampf (Hologramm) gibt eine neue Truhe.
- Entwickler: ENTWICKLER -> TRUHE: BOSS-ANKUNFT zeigt den Absturz.

## 4. Rätsel in der Welt (Konzept, nicht gebaut)

> **Ausgearbeitet in `docs/raetsel_konzept.md`** („Prüfungen der Wächterin“: Irrlichtspur, Runenreihe, Schweigender Hain, Krähenschatz, dazu neu Rissläufer und Die letzte Laterne, Designsprache, Technik, Bauplan). Die Tabelle unten ist die erste Ideensammlung.

Ziel wie bei Genshins Siegel- und Zeiträtseln: kleine Aufgaben, über die man beim Erkunden stolpert, die mit Systemen spielen, die es schon gibt, und am Ende eine Truhe aus dem Licht fallen lassen (dieselbe Ankunft wie bei den Bossen). Jede Region bekommt später eine Erkundungszahl („LICHTUNG 7/12“), die man auf der Karte sieht.

**Gemeinsames Gerüst (Vorschlag):** `data/puzzles.json` `{id, kind, tile, tier, params}`, ein `WorldPuzzle`-Knoten je Rätsel (host-autoritativ, Zustand und „gelöst“ im Speicherstand wie die Wegsteine), beim Lösen `LootChests.boss_chest`-artig `reveal(id, tier, pos)` mit Ankunftsanimation. Fehlversuche setzen mit einem kleinen violetten Leere-Puls zurück, nie mit Schaden. Kleine Rätsel -> Wurzelkiste, mittlere -> Mondsiegeltruhe, mehrstufige -> Glutreliquiar.

| Rätsel | Ablauf | Nutzt | Stufe |
|---|---|---|---|
| **Irrlichtspur** | In der Dämmerung erscheint ein kleines Irrlicht bei Leuchtpflanzen. Folgt man ihm, schwebt es weiter; zu schnell (Sprint) und es flieht, zu weit weg und es wartet. Wo es in den Boden sinkt, steigt die Truhe auf. | Leuchtflora, Schleichen, Tag/Nacht | gewöhnlich |
| **Glutschalen** | 3–5 Steinschalen im Kreis. E entzündet eine, sie brennt 15 s. Alle gleichzeitig brennend -> Truhe. Varianten: eine Schale nur mit dem Glutschwarm-Zauber, eine steht auf einem Plateau. | Laufwege, Magie (Glut) | gewöhnlich / selten |
| **Runenreihe** | Fünf Runenstelen. Eine Hinweistafel zeigt die Reihenfolge nur nachts (Glow-Schicht) oder nur, wenn ihr Schatten zur richtigen Tageszeit darauf fällt. | Glow, Tageszeit | selten |
| **Mondspiegel** | Nur nachts: ein Mondstrahl trifft einen Kristall. Mit E drehbare Kristallsplitter (wie die Kristallwände) lenken ihn auf das Siegel einer Mondsiegeltruhe. | Kristallwände, Nacht, `night_moon` | selten |
| **Blütenpfad** | Eine leuchtende Blüte berühren -> eine Spur aus 6–8 Blütenringen erscheint, 30 s Zeit, Sprint und Schattenschritt nötig. | Sprint, Schattenschritt | gewöhnlich / selten |
| **Glockenblumenlied** | Mondglocken klingen beim Schwerthieb in vier Tönen; eine singende Stele spielt eine Folge vor, man schlägt sie nach. | Kampf-Treffer auf Pflanzen | selten |
| **Leerenknoten** | Drei pulsierende Leere-Wucherungen; jede gebiert beim Treffen eine Schattenspinne. Alle drei in 60 s zerschlagen. | Nachtkreaturen, Spawn-Animation | selten |
| **Schweigender Hain** | Die Truhe steht inmitten schlafender Wächterspinnen (wie am Anfang). Nur schleichend erreichbar, Wecken = Kampf statt Truhe. | Wächterspinnen, Schleichen | selten |
| **Gewichtsplatten** | Druckplatten, die mit Ellie, einem Mitspieler oder einem hingeworfenen Stein (Q) belastet werden. Allein: Steine sammeln. | Werfen, Koop | gewöhnlich |
| **Regenschalen** | Drei steinerne Becken mit Runen füllen sich nur bei Regen; voll -> Truhe. Bei Sonne verdunsten sie langsam. | Wetter | selten |
| **Krähenschatz** | Eine Krähe mit Glitzerdingen beobachtet einen Ort. Füttert man sie, fliegt sie zu einer Stelle frischer Erde; dort mit der Hacke graben. | Begleiter/Futter, Hacke | gewöhnlich |
| **Flaschenpost** | Im See treibt eine leuchtende Flasche; mit der Angel herausziehen -> Kartenfetzen, der einen Ort markiert, dort liegt die Truhe. | Angeln, Karte | selten |
| **Spiegelnebel** (Hexenwald) | Drei gleiche Truhen im Halluzinationsnebel, nur eine ist echt (die anderen sind Trugbilder und zerfallen). Die Ohrringe der Klarheit oder ein Klarblick-Trank zeigen die echte. | `hallucinated`, Talisman/Trank | selten |
| **Die gefesselte Kammer** | Mehrstufig: drei kleine Rätsel einer Region (z. B. Glutschalen, Runenreihe, Leerenknoten) lösen je eine Kette eines Glutreliquiars an einem besonderen Ort. | alles | legendär |

### Detailpass: Innenleben und Bewegung

Die Truhen haben 16 Sprite-Posen inklusive Überschwingen und abschließender Ruhepose. Stoff und Beschläge auf der Deckelinnenseite bewegen sich mit dem Scharnier. Wurzelkiste: geflicktes Leinen mit Nähten, gefalteter Stoff, kleines Buch und rostiger Seitengriff. Mondsiegeltruhe: silbern eingefasstes Futter, verbundenes Sternbild, abgetrenntes Schriftrollenfach und Kristalle. Glutreliquiar: gestepptes weinrotes Futter, Goldpaspeln, Münzstapel, Perlenkette und Granatbrosche; dunkler Samt unter den Schätzen erhält deren Lesbarkeit. Die Inhalte sind dekorative Sprite-Details, keine Vorschau der gewürfelten Beute.

Dezentes Kerzenflackern, Lichtreflexe am Rand und sechs beim Halten kreisende Mondsiegelfacetten ergänzen die vorhandenen Effekte. Generator: `tools/art_loot_chests.py`; Tag-/Nachtvorschau: `tools/preview_loot_chests.tscn`.

## 5. Ideen für später (nicht gebaut)

- **Orte**: Truhen auf Plateaus ohne Aufgang (nur per Schattenschritt über eine Lücke), hinter einem Wasserfall, auf einem umgestürzten Stamm über dem Fluss, im Wipfel einer Schleierweide, unter einem Felsen, den man erst mit der Spitzhacke freilegt.
- **Rätsel**: Mondsiegel öffnet nur bei Vollmond oder nur nachts; drei Steine in der Nähe in der richtigen Reihenfolge berühren; ein Lied der Krähen nachpfeifen (Begleiter); Glutreliquiar braucht einen Glutschlüssel aus einem Bossfund.
- **Wächter**: ein Schattenwesen-Paar, das die Truhe nachts umkreist; Legendäre Truhen ziehen beim Öffnen die Nacht an (`NightDirector.stir`).
- **Truhenkarte**: Kartenfetzen aus gewöhnlichen Truhen markieren eine seltene Truhe auf der Karte.
- **Vergraben**: ein Hügel frischer Erde, den nur die Hacke öffnet.
- **Pro-Spieler-Beute** statt geteilter Truhe; Nachfüllen nach N Tagen (`respawn_days`).
- **Mimik**: eine Wurzelkiste, die zubeißt (passt zur Leere, braucht ein eigenes Wesen).
