# Magie – Stab und Stein (Konzept, final 2026-11-11)

Status: **Erste Stufe gebaut (2026-11-11), siehe Abschnitt 14; zweite Stufe (Glut, Nebel, Leere) in Abschnitt 15, ihre Verstärker und der Schleier gegen Bosse in Abschnitt 16, der zweite Stab (Bleichgabel) in Abschnitt 17.** Der Rest des Konzepts bleibt der Plan. Entscheidungen vom 2026-11-11 sind eingearbeitet (Abschnitt 13). Was ausdrücklich „später“ ist, steht in Abschnitt 12.

## 1. Idee in einem Satz

Ellie trägt einen **Zauberstab** in der Hotbar; der Stab selbst zaubert nichts, er ist **Fassung**. Die Magie steckt in **Kristallen**: ein **Zauberkristall** trägt den Zauber und lädt sich nach jedem Wirken selbst wieder auf, ein **Verstärkerkristall** daneben verändert diesen Zauber (mehr Geschosse, schneller wieder bereit, größere Fläche …). Beide Kristallarten gibt es in fünf Stufen, und man erkennt auf den ersten Blick, welche Art welche ist.

## 2. Warum das gut in Shadowspore passt

- **Licht ist Land.** Magie ist tragbares Licht: ein Lichtzauber kann für ein paar Sekunden einen echten Lichtkreis setzen, den die Nacht respektiert wie eine Laterne der Stadt (5.1).
- **Kristalle sind schon überall:** Kristallfelsen, Adern in Wänden, die Kristalle der Wegsteine, Leerenkristalle im Steinbruch, Splitter und Kerne der Schattenwesen. Magiekristalle setzen das fort.
- **Zwei Hexen, zwei Handwerke:** Esma macht Talismane und Tränke. Die **Seehexe** (Arbeitsname; Hütte später unten links am Hexenwald-See, Seemitte (734, 908)) macht Stäbe und Kristalle. Beide kennen sich.
- **Neuer Loot ohne neuen Ausrüstungsslot**, und **Koop-Rollen**: ein Stab mit Heilkristall macht aus einer Mitspielerin die Heilerin im Bosskampf.

## 3. Der Stab

### 3.1 Halten und Bedienen

- Ein Stab ist ein Hotbar-Item wie Axt, Spitzhacke oder Angel (`kind: "staff"`, `hotbar: true`). Wählt sie seinen Slot, hält sie den Stab statt des Schwerts (`InventoryComponent.active_stack()`). Wechsel Schwert ↔ Stab über die Zahlentasten. Kein neuer Ausrüstungsslot.
- **LMT wirkt den Zauber** des eingesetzten Zauberkristalls, gezielt mit `InputManager.aim_vector()`.
- **RMT ist vorerst frei** (reserviert für spätere Stäbe mit einer zweiten Zauberfassung).
- Mit dem Stab wird nicht geschlagen.
- Der Schattenschritt bricht jedes Zaubern ab (gleiche Regel wie bei Hieben).

### 3.2 Zwei Fassungen

Jeder Stab hat **zwei Arten von Fassungen**:

| Fassung | nimmt | Aufgabe |
|---|---|---|
| **Zauberfassung** | genau einen Zauberkristall | der Zauber auf LMT |
| **Verstärkerfassung** | genau einen Verstärkerkristall | verändert den Zauber der Zauberfassung |

Ein Zauberkristall passt nie in eine Verstärkerfassung und umgekehrt; die Form der Fassung zeigt es (siehe 6.4). Ein Verstärker, der nicht zum Zauber passt (Beispiel: GABEL auf einem Heilkreis), sitzt im Stab, wirkt aber nicht; die Karte sagt „WIRKT NICHT AUF WURZELGRUND“.

### 3.3 Der erste (und vorerst einzige) Stab: Hexenulmenstab

- **Hexenulmenstab** (Holz der Hexenulme `hag_tree`, gewöhnlich). 1 Zauberfassung + 1 Verstärkerfassung, nimmt Kristalle **aller fünf Stufen** (zum Testen ohne Grenze).
- Aussehen: ein gedrehter, dunkler Ast der Hexenulme mit der violetten Rinde und den kurzen Adern aus dem Hexenwald. Oben öffnet sich der Ast zu einer **Krone aus drei gekrümmten Zweigen**, die den Zauberkristall aufrecht umklammern. Eine Handbreit darunter sitzt in einem **Astknoten** eine flache runde Mulde für den Verstärker. Leer sieht man die leere Krone und die leere Mulde.
- Der Stab hat **keine eigenen Werte**. Abklingzeiten, Stärke und alles Weitere kommen in diesem ersten Schritt nur aus den Kristallen. Weitere Stäbe mit eigenen Werten (Grad, Takt, Kraft, Eigenheit) sind später (12.1).
- Bezug am Anfang: ENTWICKLER-Knopf „ZAUBERSTAB + ALLE KRISTALLE“. Später baut ihn die Seehexe.

## 4. Die Kristalle

### 4.1 Gemeinsame Regeln

- Jeder Kristall ist ein Item. **Jede Stufe ist ein eigenes Item** (wie bei den Tränken: `crystal_wisp_1` … `crystal_wisp_5`, `gem_fork_1` … `gem_fork_5`). So stapeln sie sauber, und Preis, Seltenheit und Icon hängen an der ID. Stapel bis 10.
- **Seltenheit = Stufe**, für beide Arten gleich:

| Stufe | Seltenheit | Zauberkristall | Verstärkerkristall |
|---|---|---|---|
| I | gewöhnlich | **SPLITTER** | **ROHSCHLIFF** |
| II | ungewöhnlich | **SCHERBE** | **TROPFEN** |
| III | selten | **KRISTALL** | **LINSE** |
| IV | episch | **HERZSTEIN** | **FACETTE** |
| V | legendär | **STERNSTEIN** | **KRONE** |

- Der Name eines Kristalls ist „Stufe + Zauber“, z. B. „SCHERBE DER TAUWELLE“, „LINSE DER EILE“.
- Die Stufe macht stärker **und** gibt bei III und V je eine neue Eigenschaft (4.3, 4.5). Ein Aufstieg soll sich nach mehr anfühlen als nach Prozenten.

### 4.2 Aufladen (die Abklingzeit trägt der Kristall)

- **Jeder Zauberkristall hat seine eigene Abklingzeit.** Nach dem Wirken ist er leer und lädt sich selbst wieder auf; dann ist er bereit. Höhere Stufen laden schneller.
- Ab **HERZSTEIN (IV)** speichern manche Kristalle **zwei Ladungen** (zweimal hintereinander wirken, jede lädt einzeln nach). Steht beim jeweiligen Zauber.
- Anzeige: der Kristall an der Stabspitze ist nach dem Wirken **aus** (dunkel und trüb). Ab etwa der Hälfte der Ladezeit glimmt er schwach und wird heller, im letzten Drittel **blitzt er immer öfter kurz auf**; ist er bereit, **blitzt er hell auf** (Lichtkreuz, leiser Klang) und leuchtet danach wieder wie vorher. (Ein Ring auf dem Hotbar-Slot ist noch nicht gebaut.)
- Der Verstärker EILE verkürzt die Aufladung (4.5).
- **Herausnehmen setzt die Ladung zurück:** wer einen Kristall aus dem Stab nimmt und wieder einsetzt, beginnt leer. So lohnt kein Tauschen, um Abklingzeiten zu umgehen.
- Die Ladung läuft weiter, wenn der Stab nicht in der Hand ist.
- Einen eigenen Namen und eine eigene Leiste für „Zauberkraft“ gibt es vorerst **nicht**; nur das Aufladen. Ob später eine Kraft dazukommt, wird getrennt entschieden (12.2).

### 4.3a Das Wesen der fünf Schulen (2026-11-11)

Jede Schule hat ein Gefühl, eine Aufgabe im Spiel und eine eigene Sprache der Mechanik. Neue Zauber werden daran gemessen: passt er nicht ins Wesen seiner Schule, gehört er in eine andere.

| Schule | Gefühl | Aufgabe | Wie sie wirkt | Was sie nie tut |
|---|---|---|---|---|
| **NATUR** (Hexengrün) | Heilung, Nähe, Wärme, Geborgenheit, Wachstum, Geduld | die Gruppe am Leben halten | Zonen am Boden, Wirkung über Zeit, **stärker, je näher man zusammensteht**, Bänder zwischen Spielern | angreifen oder zerstören |
| **LICHT** (Laternen-Türkis) | Sicherheit, Schutz, Wachsamkeit, Wahrheit | gegen die Leere schützen und sehen | Lichtkreise, die die Nacht respektiert, Schilde und Schutz statt Heilung, Schaden **nur gegen Schattenwesen**, Enthüllen (Verborgenes, Trugbilder, die Halluzinationen des Hexenwalds, Nebel auf der Karte) | heilen (das ist Natur), Tiere oder die Welt verletzen |
| **GLUT** (Bernstein) | Kraft, Mut, Zorn, Leidenschaft, Antrieb | Schaden machen und vorangehen | Feuer, Fläche, Brennen über Zeit, Wucht und Rückstoß, Mut für sich selbst (schneller, stärker für kurze Zeit) | leise oder vorsichtig sein |
| **NEBEL** (Violett-Grau) | Täuschung, Verborgenheit, Traum, Geheimnis, Wandel | dem Kampf ausweichen, ihn lenken | Tarnung, Trugbilder, Verwirren und Verlangsamen, Plätze tauschen, Schleichen | direkt Schaden machen |
| **LEERE** (Magenta) | Hunger, Verlust, das Verbotene, Macht mit Preis | großer Gewinn um einen Preis | Sog, durchschlagender Schaden, Lebensraub, Male; **kostet immer etwas** (Leben, Licht, Sicherheit) | sicher oder umsonst sein |

**Gegensätze:** LICHT ↔ LEERE (schützen gegen verschlingen), NATUR ↔ GLUT (wachsen lassen gegen verzehren; die Wärme der Natur ist der Herd, die der Glut das Feuer), NEBEL ↔ LICHT als zweite Achse (verbergen gegen enthüllen). Gegensätze kann man später für Verstärker und Kombinationen nutzen, z. B. ein Lichtzauber hebt einen Nebel auf.

**Was das für die schon gebauten Zauber heißt:**
- *Bannlicht* passt genau: ein Schutzkreis, der nur Schattenwesen verbrennt und ab Stufe III die Nacht fernhält.
- *Wurzelgrund* passt als Heilung und Geborgenheit. Vorschlag für „Nähe“: jede weitere Person im Kreis erhöht die Heilung aller darin ein wenig.
- *DORNEN* (Wurzelgrund III) macht Schaden und widerspricht damit dem Wesen der Natur. Vorschlag: aus DORNEN wird **SCHUTZWALL**: Die Wurzeln stoßen Schattenwesen aus dem Kreis hinaus, statt sie zu verletzen.

### 4.3 Zauberkristalle: die fünf Schulen und ihre Zauber

Jede Schule hat eine Grundfarbe; **jeder Kristall einer Schule ist leicht anders getönt** (Tönung in der Tabelle), damit zwei Heilkristalle nebeneinander unterscheidbar sind, aber klar zur selben Familie gehören.

Schattenwesen nehmen von **Licht** +50 % Schaden, von **Leere** −50 %. Bosse sind gegen Blenden, Festhalten und Verlangsamen nur kurz anfällig (ein Drittel der Dauer). **Kein Zauber verletzt Tiere** (Regel „keine Tiere töten“: Zauber gehen durch sie hindurch, scheuchen sie nur). Kein Zauber trifft Mitspieler, außer zum Heilen.

Zahlen sind Startwerte für die Balance (Stufe I → Stufe V). „Schaden 1,0“ = ein Hieb des einfachen Schwerts.

#### LICHT – Laternen-Türkis

| Kristall | Tönung | Wirken | Wirkung | Aufladen I → V | Stufe III | Stufe V | eingraviertes Zeichen |
|---|---|---|---|---|---|---|---|
| **Irrfunke** | grünstichiges Türkis | sofort, Geschoss | Lichtfunke, Schaden 0,9 → 1,8 | 0,8 s → 0,45 s | lenkt leicht zum nächsten Ziel | springt auf ein zweites Ziel | vierzackiger Funke mit kurzem Schweif |
| **Laternenkreis** | warmes Lampen-Türkis | kurz halten (0,5 s), Boden | echter Lichtkreis 48 → 80 px für 8 → 18 s; Schattenwesen meiden ihn, nichts entsteht darin | 45 s → 28 s | Wesen im Kreis werden langsamer | 2 Ladungen | Ring mit einer kleinen Flamme in der Mitte |
| **Blendstrahl** | fast weißes Türkis | sofort, Kegel | blendet Schattenwesen 1 → 2,2 s (verlieren das Ziel, Ausholen bricht ab), wenig Schaden | 12 s → 7 s | Kegel breiter | Geblendete nehmen +20 % Schaden | offenes Auge mit drei Strahlen |

#### WURZEL – Hexengrün (die Heiler-Schule)

| Kristall | Tönung | Wirken | Wirkung | Aufladen I → V | Stufe III | Stufe V | eingraviertes Zeichen |
|---|---|---|---|---|---|---|---|
| **Tauwelle** | Tau-Minzgrün | sofort, sucht Ziel | heilende Lichtperle fliegt zur Mitspielerin am nächsten zum Cursor (Reichweite 160 px), heilt 8 % → 18 % ihrer max. Gesundheit; ohne Mitspielerin heilt sie Ellie zur Hälfte | 4 s → 2,5 s | springt auf eine zweite Person | 2 Ladungen, Überschuss wird Überheilung | Tropfen mit einem Blatt daran |
| **Wurzelgrund** | tiefes Moosgrün | kurz halten (0,6 s), Boden | Kreis aus Wurzeln 40 → 64 px, alle Spieler darin regenerieren 2 % → 4 % pro s für 6 s | 20 s → 12 s | Kreis hält 9 s | Spieler darin nehmen 15 % weniger Schaden | Kreis, aus dem drei Wurzeln nach unten wachsen |
| **Rankenband** | Gelbgrün | halten, Band | leuchtende Ranke zu einer Mitspielerin (Reichweite 140 px), solange LMT gehalten: 3 % → 6 % ihrer max. Gesundheit pro s; reißt bei zu viel Abstand oder Sichtverlust; Ellie geht dabei langsam (60 %); höchstens 8 s am Stück | 10 s nach dem Loslassen → 6 s | reißt erst bei 180 px | heilt Ellie ein Drittel mit | zwei Punkte, durch eine Spiralranke verbunden |

#### GLUT – Bernstein

| Kristall | Tönung | Wirken | Wirkung | Aufladen I → V | Stufe III | Stufe V | eingraviertes Zeichen |
|---|---|---|---|---|---|---|---|
| **Glutsame** | Bernstein-Orange | sofort, Bogenwurf | Samen platzt im Kreis 24 → 36 px, Schaden 1,2 → 2,4, setzt VERBRENNEN (`burn`) | 3 s → 1,8 s | Kreis brennt 2 s nach | 2 Ladungen | Samenkorn mit Flamme |
| **Funkenregen** | Goldgelb | kurz halten (0,5 s), Fläche am Cursor | 5 → 9 kleine Einschläge über 1,5 s, je Schaden 0,4 → 0,7 | 14 s → 9 s | Einschläge suchen Gegner | jeder Einschlag setzt VERBRENNEN | drei fallende Funken |
| **Aschenwand** | tiefes Glutrot | kurz halten (0,6 s), Linie quer zum Zielen | Glutwand 48 → 80 px lang, 5 → 8 s; Schattenwesen wollen nicht hindurch, wer durchgeht, brennt | 30 s → 20 s | Wand länger und brennt stärker | gezogene Gegner prallen ab | drei Flammensäulen nebeneinander |

#### NEBEL – Violett-Grau

| Kristall | Tönung | Wirken | Wirkung | Aufladen I → V | Stufe III | Stufe V | eingraviertes Zeichen |
|---|---|---|---|---|---|---|---|
| **Schleier** | Grau-Lila | sofort, auf sich | 5 → 10 s deutlich kleinerer Alarmradius (`StealthComponent.alarm_scale` × 0,6 → 0,35) | 30 s → 18 s | wirkt auch auf Mitspieler bis 48 px | erster Treffer aus dem Schleier +50 % | geschlossenes Auge unter einem Bogen |
| **Trugbild** | kühles Blauviolett | sofort, am Cursor | ein Nebel-Abbild von Ellie lenkt Gegner 3 → 6 s ab (Klon-Technik von Morwenna) | 25 s → 15 s | Abbild läuft langsam weiter | zerplatzt mit kurzem Blenden | zwei gespiegelte Gestalten |
| **Nebelhauch** | blasses Lavendel | sofort, Kegel | Gegner im Kegel 3 → 5 s um 35 % → 55 % langsamer, wenig Schaden | 10 s → 6 s | Kegel breiter | stoppt Ausholen kurz | Spirale aus einem Hauch |

#### LEERE – Magenta (stark, mit Preis)

| Kristall | Tönung | Wirken | Wirkung | Aufladen I → V | Stufe III | Stufe V | eingraviertes Zeichen |
|---|---|---|---|---|---|---|---|
| **Risszahn** | heißes Magenta | kurz halten (0,4 s), Linie | durchschlagender Riss 90 → 140 px, Schaden 2,0 → 3,6, **kostet 4 % der eigenen Gesundheit** (nie die letzte) | 6 s → 3,5 s | kostet nur noch 2 % | 2 Ladungen | zackiger Riss wie ein Fangzahn |
| **Sog** | dunkles Purpur | kurz halten (0,5 s), Fläche | zieht Gegner in 56 → 80 px zur Mitte zusammen, kleiner Schaden | 18 s → 11 s | Gezogene sind 1 s benommen | danach platzt der Sog (Schaden 1,5) | Spirale nach innen mit einem Punkt |
| **Leerenmal** | Rosa-Violett | sofort, Geschoss | markiert ein Ziel 6 s; der nächste **Schwerttreffer** darauf +60 % → +120 % | 8 s → 5 s | Mal springt nach dem Treffer weiter | Mal-Treffer heilt Ellie ein wenig | Ring mit einem Kreuz darin (Brandzeichen) |

Das sind **15 Zauberkristalle × 5 Stufen = 75 Items**.

### 4.4 Wie Zauberkristalle aussehen (Set „gewachsen“)

Zauberkristalle sind **natürlich gewachsen**: aufrecht, spitz, unregelmäßig, klar und **gesättigt in ihrer Schulfarbe**, mit Licht im Inneren. Das Zeichen schwebt **im** Kristall als leuchtender Einschluss.

| Stufe | Form | Klarheit | Zeichen |
|---|---|---|---|
| I SPLITTER | ein kleiner, schräg abgebrochener Splitter, eine Spitze | trüb, milchige Flecken | schwach, nur der Umriss glimmt |
| II SCHERBE | größere Scherbe mit einer zweiten kleinen Spitze daneben | halb klar | lesbar, gleichmäßig glimmend |
| III KRISTALL | sauberes, sechskantiges Prisma mit Spitze, eine Kante hell | klar | hell, mit hellerem Kern |
| IV HERZSTEIN | doppelspitziges Prisma mit zwei kleinen Seitenkristallen, ein leuchtender Kern im Inneren | sehr klar | strahlt, kleiner Lichthof im Kristall |
| V STERNSTEIN | Sternbündel aus mehreren Spitzen um einen Mittelkristall | glasklar | brennt hell; in der Welt und am Stab umkreisen ihn ein, zwei Funken |

### 4.5 Verstärkerkristalle: das zweite Set

Verstärker gehören keiner Schule an. Sie haben eine **Wirkungsfamilie**, die ihren Schimmer bestimmt, und passen nur zu bestimmten Zaubern („passt zu“).

| Verstärker | Familie (Schimmer) | Wirkung I → V | Stufe III | Stufe V | passt zu | eingraviertes Zeichen |
|---|---|---|---|---|---|---|
| **Gabel** | Form (Rosé) | +1 Geschoss (−40 % Schaden je Geschoss) → +2 (−25 %) | +2 Geschosse | Geschosse fächern breiter, −20 % | Irrfunke, Glutsame, Leerenmal | dreizinkige Gabel |
| **Weite** | Form (Rosé) | Fläche/Länge +15 % → +45 % | Wirkdauer +15 % | Rand der Fläche wirkt doppelt | Kreise, Flächen, Wände, Kegel | Ring mit vier Pfeilen nach außen |
| **Eile** | Zeit (Silberblau) | Aufladen −8 % → −28 % | – | bereit werden heilt 1 % | alle | Sanduhr |
| **Echo** | Zeit (Silberblau) | Zauber wiederholt sich nach 0,6 s mit 30 % → 60 % | Echo zielt neu | 2 Echos | Geschosse, Kegel, Linien (nicht Kreise, Bänder, Schleier) | drei konzentrische Bögen |
| **Dauer** | Zeit (Silberblau) | Wirkdauer +15 % → +50 % | – | Ende der Wirkung pulst noch einmal | Kreise, Wände, Bänder, Schleier, Trugbild, Male | Ring mit langem Schweif |
| **Wucht** | Kraft (Gold) | Schaden +10 % → +35 % | +Rückstoß | Treffer mit Wucht brechen leichtes Ausholen | Schadenszauber | Keil nach oben |
| **Nachglut** | Kraft (Gold) | Treffer setzen leichtes VERBRENNEN (20 % → 60 % Chance) | stärkeres Brennen | Brennende nehmen +10 % Zauberschaden | Schadenszauber außer Glut | kleine Flamme in einem Ring |
| **Bindung** | Leben (Perlgrün) | 3 % → 10 % des Zauberschadens heilen Ellie | – | Überschuss heilt die nächste Mitspielerin | Schadenszauber | Herz mit einem Faden |
| **Gnade** | Leben (Perlgrün) | Heilung +10 % → +30 % | Heilzauber erreichen +1 Person | geheilte Spieler 3 s lang 10 % weniger Schaden | Heilzauber | zwei Tropfen, die sich berühren |

Das sind **9 Verstärker × 5 Stufen = 45 Items**.

Beispiele: Tauwelle + Gnade = Gruppenheilerin. Irrfunke + Gabel = Funkenfächer. Laternenkreis + Dauer = lange Lichtinsel in der Nacht. Leerenmal + Echo = zwei Male hintereinander.

### 4.6 Wie Verstärkerkristalle aussehen (Set „geschliffen“)

Verstärker sind **von Hand geschliffen**: rund, symmetrisch, flach liegend. Der Körper ist **milchig wie Mondstein oder Opal** (hell, kühl, kaum gesättigt), darüber liegt der **Schimmer seiner Familie**: Rosé, Silberblau, Gold oder Perlgrün. Das Zeichen ist **in den Stein eingeschliffen**: eine feine, silberweiß leuchtende Gravur, die im Stein liegt, nicht obendrauf.

| Stufe | Form | Oberfläche | Zeichen |
|---|---|---|---|
| I ROHSCHLIFF | grob gerundeter Kiesel, leicht schief | matt | schwach eingeritzt |
| II TROPFEN | polierter Tropfen (Cabochon) | glänzend, ein Lichtpunkt | sauber eingeschliffen |
| III LINSE | runde Linse mit abgesetztem Rand | glänzend, Schimmer wandert | klar, leicht leuchtend |
| IV FACETTE | achteckiger Facettenschliff | Farbspiel in den Facetten | leuchtet, bricht sich in zwei Facetten |
| V KRONE | Rosenschliff mit Krone, kleine Strahlen | volles Farbspiel, Glitzer | strahlt, im Stab ein ruhiger Lichtpuls |

### 4.7 Die beiden Sets unterscheiden

Man soll ohne Lesen sehen, was ein Kristall ist. Die zwei Sets unterscheiden sich in vier Dingen auf einmal:

| | Zauberkristall | Verstärkerkristall |
|---|---|---|
| **Umriss** | aufrecht, spitz, unregelmäßig | rund oder achteckig, symmetrisch, flach |
| **Körper** | klar, kräftig in der Schulfarbe | milchig hell (Mondstein/Opal) mit Farbschimmer |
| **Zeichen** | leuchtender Einschluss in Schulfarbe, schwebt im Inneren | silberweiße Gravur, eingeschliffen |
| **Licht** | leuchtet von innen (Kern) | schimmert an der Oberfläche |

Innerhalb eines Sets gehören alle Stufen sichtbar zusammen (gleiche Form-Familie, gleiche Lichtregel), und die Stufe liest man an Größe, Klarheit und Ausbau der Form. Der Seltenheitsrand des Slots (`rarities.json`) kommt wie bei allen Items dazu.

## 5. Wo Magie die Welt berührt

### 5.1 Nacht
- **Laternenkreis** ist ein vorübergehender Lichtkreis: `TownManager.light_depth` / `spawn_blocked` fragen zusätzlich die aktiven Zauber-Lichtkreise ab (eigener kleiner Anbieter, nichts davon in den Stadtdaten gespeichert). Gereizte (`excited`) Wesen dürfen hinein, wie in der Stadt.
- **Zaubern ist hell und laut:** jedes Wirken zählt zum Lockreiz der Nacht (`NightDirector`, wie Sprinten und Hiebe; Schleier ausgenommen). Ein Lichtzauber im Dunkeln verrät sie.

### 5.2 Hexenwald
- Im Halluzinationsnebel lügt manchmal die Ladeanzeige (ein Kristall blitzt „bereit“ auf und ist es nicht), wie heute die Lebensranke. Klarblick und die Ohrringe heben es auf.

### 5.3 Sonst
- Kein Zaubern beim Schwimmen, im Baumodus, beim Angeln, beim Essen/Pflücken (gleiche Sperren wie für Hiebe).
- Zauber treffen Schattenwesen, Bosse und Übungspuppen, keine Tiere und keine Pflanzen (kein Ernten mit Magie).

## 6. Aussehen und Gefühl

### 6.1 Ellie zaubert
- Zwei Grundbewegungen: **Wurf** (kurz, Stab nach vorn, für Geschosse und Sofortzauber; mit den Beinvarianten wie bei den Hieben, damit sie im Gehen zaubert) und **Halten** (Stab hoch oder auf den Boden gestoßen, für Kreise, Flächen, Bänder; verlangsamt sie).
- Neues Körper-Sheet (wie `player_heavy.png`), gemacht vom Art-Subagenten.

### 6.2 Effekte
- Alle Zaubereffekte sind ungeschminkt (`Unlit`) in der Tönung des Kristalls, im bestehenden Vokabular: Funken, Ringe, Halos aus `VoidGlow`/`SlashArc`-Bausteinen, ganze Pixel. Kein Rauch.
- Pro Schule eine eigene Handschrift: Licht = klare Funken und Ringe, Wurzel = wachsende Ranken und Blätter, Glut = Glutkörner und Funkenbögen, Nebel = Schleier aus gerasterten Bändern, Leere = Risse im Stil des `void_rift`-Shaders.

### 6.3 Der Stab in der Hand
- Bild aus `tools/art_weapons.py` wie alle gehaltenen Items (gedrehtes Sheet, keine Laufzeitdrehung). Das Skript schreibt pro Winkelzelle zusätzlich die Punkte **Krone** und **Knoten**.
- Die eingesetzten Kristalle werden zur Laufzeit als kleines Pixelbild (4–5 px, aus den Kristallbildern abgeleitet) an diese Punkte gesetzt, mit Ladezustand (dunkel → voll → Aufblitzen) und unbeleuchtetem Glimmen.

### 6.4 Kristall-Kunst (Art-Subagent)
- Ein Skript `tools/art_crystals.py` erzeugt **alle 120 Kristalle aus Geometrie**: Zauberkristalle als Prismen/Splitter mit Facetten, Verstärker als Rundschliffe, beleuchtet von links oben wie alle Icons, Umriss `1b1a2e`.
- **Pro Kristall drei Bilder:** Icon 16×16 (Inventar, Hotbar; Prüfung `check_icon`), Detailbild 32×32 (Karte im Tooltip, Fassungsansicht; hier liest man das Zeichen gut) und ein Glow-Bild (nur die leuchtenden Pixel).
- **Das eingravierte Zeichen** liegt als kleine Vektorform in zwei Größen vor (5×5 für das Icon, 9×9 für das Detailbild) und wird **in das Volumen gerendert, nicht aufgemalt:**
  - Zauberkristall: das Zeichen wird an jeder Facettenkante um einen Pixel versetzt (Lichtbrechung), ist hinter hellen Facetten-Glanzlichtern teilweise verdeckt, in der Mitte heller, und auf niedrigen Stufen von der Trübung geschluckt.
  - Verstärker: das Zeichen ist eine eingetiefte Linie mit heller Unterkante und dunkler Oberkante (graviert), im Inneren leuchtet die Linie silberweiß, auf FACETTE und KRONE bricht sie sich an den Facetten.
  - Das Zeichen muss zum Zauber passen (Spalte „eingraviertes Zeichen“ in 4.3 und 4.5) und bei allen fünf Stufen dasselbe sein.
- **Farben:** jede Schule eine Rampe; jeder Kristall verschiebt sie leicht (Tönung, etwa ±15° Farbton und etwas Helligkeit, in den Daten als `tint`). Verstärker: eine gemeinsame milchige Rampe plus Familienschimmer.
- Kontaktbogen `docs/img/crystals.png`: Zeilen = Kristalle, Spalten = Stufen I–V, beide Sets untereinander, so dass man den Unterschied und die Zusammengehörigkeit auf einen Blick prüfen kann.

### 6.5 Ton
- `tools/audio_magic.py`: pro Schule Wirken und Treffen, Kristall bereit (ein heller Klang, je Stufe etwas reicher), Kristall einsetzen (Holz klemmt um Stein), Verstärker einsetzen (Stein rastet in Mulde).

## 7. Bedienung im Inventar

- **Einsetzen:** Kristall auf dem Cursor, Klick auf den Stab → er geht in die passende Fassung (Zauber oder Verstärker). Ist sie belegt, tauschen sie: der alte Kristall kommt auf den Cursor.
- **Herausnehmen:** Rechtsklick auf den Stab öffnet neben dem Slot eine kleine Fassungsansicht (der Stabkopf groß, Krone und Mulde mit den 32er-Kristallbildern); dort nimmt man Kristalle mit Klick heraus.
- Einsetzen geht überall, nur nicht während eines Zaubers. Herausnehmen setzt die Ladung zurück (4.2).
- **Karte des Stabs** (`ItemTooltip`): beide Fassungen mit Kristall, Stufe, Ladezustand; beim Verstärker „WIRKT AUF …“ oder „WIRKT NICHT AUF …“.
- **Karte eines Kristalls:** Name, Stufe, Schule/Familie, Werte, Aufladezeit, „passt zu“, und was Stufe III und V bringen (noch nicht erreichte Zeilen gedimmt).

## 8. Woher Kristalle kommen (Ausblick)

| Quelle | Was |
|---|---|
| **Schattenwesen** | seltene Leere- und Nebelsplitter (Brecher eher Glut) |
| **Mine** | Kristalladern geben Licht- und Leerekristalle, tiefer = höhere Stufe; Kisten auch Verstärker |
| **Orte und Pflanzen** | Wurzelsplitter an Leuchtpilzen und Mondbirken |
| **Der See** | nachts am Ufer und selten beim Angeln im Hexenwald-See |
| **Bosse** | besondere Kristalle (Mornath: Federsturm, Morwenna: Spiegelscherbe) |
| **Questtafel** | seltene Kristalle als Belohnung |
| **Seehexe** | verkauft wenige Splitter und Rohschliffe, schleift höher (später) |

Bis die Quellen gebaut sind, kommt alles aus dem ENTWICKLER-Menü.

## 9. Netzwerk und Technik

| Teil | Wo |
|---|---|
| Daten | `data/spells.json`: Schulen (Farbrampen), Zauberkristalle (Schule, `tint`, Wirkart, Werte je Stufe, Eigenschaften III/V, Ladungen, Zeichen-ID), Verstärker (Familie, Werte je Stufe, `fits`), Stab `staff_hag_elm` (Fassungen). Items in `data/items.json` (`kind: "staff"` / `"crystal"` / `"gem"`, Block `crystal: {spell, tier}` bzw. `gem: {mod, tier}`) |
| Regeln | `SpellRules` (rein, getestet): Werte eines Kristalls bei Stufe n, Verstärker anwenden, Passt-Prüfung, Aufladezeit |
| Kristalle im Stab | Extras im Stab-Stack wie `r` bei der Verfeinerung: `{"id": "staff_hag_elm", "count": 1, "spell": "crystal_dew_3", "gem": "gem_mercy_2"}`; `Items.extras`, `SaveGame._stack`, `ItemDrop`, Werfen und Sortieren tragen es mit (ein Stab mit Kristallen stapelt nicht) |
| Einsetzen | neue `InventoryComponent`-Ops `socket` / `unsocket` (Host prüft Art und Fassung) |
| Zaubern | `SpellComponent` (Kind jedes Players, wie `AttackComponent`): Besitzer schickt Absicht + Zielrichtung (+ Zielspieler bei Heilung), Host prüft Ladung, Sperren, Reichweite, Sichtlinie und löst aus; alle Peers spielen den Effekt. Geschosse über den vorhandenen Projectile-Spawner (Muster `ResonanceWave`), Kreise/Wände/Bänder als replizierte Knoten unter dem Level |
| Ladungen | im `SpellComponent` auf dem Host je Spieler und Fassung, an den Besitzer gespiegelt (Anzeige); nicht gespeichert (nach dem Laden sind Kristalle bereit) |
| Heilen | `HealthComponent.heal` / `regen` mit Quelle |
| Lichtkreis | kleiner Anbieter, den `TownManager.light_depth/spawn_blocked` zusätzlich fragen |
| Lockreiz | Wirken meldet Lärm an den `NightDirector` |
| Status | `burn` (vorhanden), neu `blinded`, `slowed`, `void_mark` in `data/status_effects.json` für Gegner |
| UI | Ladering am Hotbar-Slot, Fassungsansicht, `ItemTooltip`-Zeilen, Cursor-Look „Zielen mit Stab“ (`GameCursor`), Heilziel-Markierung über der Mitspielerin |
| Dev | ENTWICKLER: „ZAUBERSTAB + ALLE KRISTALLE“, „KRISTALLE AUFLADEN“ |
| Tests | `tools/test_magic.tscn` (Regeln aller 15 × 5 und 9 × 5, Einsetzen/Tauschen/Zurücksetzen, Host-Prüfung, Heilziel, Lichtkreis gegen `spawn_blocked`, Speichern), `tools/test_magic_network.tscn` (zwei Prozesse), Kontaktbogen der Kristalle |

## 10. Bauplan

1. **Daten und Regeln:** `spells.json`, Items mit Platzhalter-Icons, `SpellRules`, Stack-Extras, `socket`/`unsocket`, Tooltip-Zeilen. Test.
2. **Zaubern:** `SpellComponent`, Aufladen, Hexenulmenstab in der Hotbar, zwei Zauber spielbar (Irrfunke, Tauwelle) mit einfachen Effekten, Netzwerk. Test.
3. **Kunst I:** `art_crystals.py` (alle 120 Kristalle, Kontaktbogen), Hexenulmenstab in `art_weapons.py` mit Kronen-/Knotenpunkten, Kristalle am Stab.
4. **Alle Zauber** Schule für Schule mit ihren Effekten, Laternenkreis an die Nacht angebunden, neue Statuseffekte.
5. **Alle Verstärker.**
6. **Kunst II:** Zauber-Sheet für Ellie, Ton.
7. **Balance**, dann Quellen (Loot, Mine, Bosse, Tafel).

## 11. Balance-Anker

- Fernkampf ist sicherer als das Schwert, deshalb liegt der Schaden pro Sekunde eines Zauberkristalls **unter** dem eines gleich seltenen Schwerts; Magie glänzt durch Wirkung (Licht, Heilung, Kontrolle), nicht durch rohen Schaden.
- Die Wundpause der Tränke gilt **nicht** für Heilzauber; die Aufladezeit begrenzt sie.
- Stab-Wechsel (Schwert ↔ Stab) ist schnell, aber nicht frei: ein Zauber direkt nach dem Wechsel braucht 0,25 s Ziehzeit.

## 12. Später (bewusst nicht in diesem Konzept)

1. **Weitere Stäbe** aus anderen Hölzern mit eigenen Werten (Grad = höchste Stufe, Takt, Kraft, Eigenheit, evtl. zweite Zauberfassung auf RMT). Wird getrennt besprochen.
2. **Eine Zauberkraft** mit Namen und Anzeige, falls das Aufladen allein nicht reicht.
3. **Kristalle wachsen lassen** (Resonanz durch Benutzen, Schleifen bei der Seehexe, oder Verschmelzen 3 → 1).
4. **Die Seehexe**, ihre Hütte unten links am Hexenwald-See und ihre eigenen Tränke (Vorschlag: Wurftränke). Konzept für Ort, Figur, Laden und Einstiegsquest: `docs/seehexe_konzept.md` (2026-11-11).
5. Ein Zweig MAGIE im Fähigkeitsgraph.
6. Weitere Zauber (z. B. Dornenschlinge in Wurzel, eine Wasser-Schule am See).

## 13. Entscheidungen (2026-11-11)

1. **Kristalle tragen die Magie** und ihre **eigene Abklingzeit**: sie laden sich selbst wieder auf. Kein Mana, keine Kraft im Stab; ein Name für die Zauberkraft kommt später.
2. **Stufennamen** der Zauberkristalle: SPLITTER · SCHERBE · KRISTALL · HERZSTEIN · STERNSTEIN.
3. **Fünf Schulen:** Licht, Wurzel, Glut, Nebel, Leere.
4. **Der Stab liegt in der Hotbar.**
5. **Zuerst nur ein Stab:** Hexenulmenstab mit **zwei Fassungen**, eine für einen **Zauberkristall**, eine für einen **Verstärkerkristall**. Weitere Stäbe später.
6. **Zwei Kristall-Linien** (Zauber, Verstärker), jede mit **eigenem Set in fünf Seltenheiten**, innerhalb des Sets zusammenpassend, zwischen den Sets klar unterscheidbar (4.4, 4.6, 4.7). Verstärker-Stufen: ROHSCHLIFF · TROPFEN · LINSE · FACETTE · KRONE.
7. **Kunst:** jeden Kristall gibt es in jeder Stufe; Kristalle derselben Schule variieren leicht in der Farbe; jeder trägt ein **zum Zauber passendes Zeichen, das im Kristall liegt** (eingeschlossen bzw. eingeschliffen), nicht aufgemalt.

## 14. Gebaut (2026-11-11): die erste Stufe

Bewusst klein angefangen: **ein Stab, zwei Zauberkristalle, zwei Verstärker**, je fünf Stufen (20 Steine). Die übrigen Zauber und Verstärker aus 4.3/4.5 sind noch nicht gebaut.

| Stein | Schule/Familie | Wirkung |
|---|---|---|
| **Bannlicht** (`crystal_banish_1..5`) | Licht | ein stehender Lichtschein um Ellie, Schattenwesen darin verbrennen; III BANNKREIS (die Nacht behandelt ihn wie eine Laterne), V SONNENKERN (Lichtring alle 2 s) |
| **Wurzelgrund** (`crystal_roots_1..5`) | Wurzel | an der gezielten Stelle (110 px) brechen wilde Wurzeln aus der Erde, wer im Kreis steht wird jede Sekunde geheilt; III DORNEN, V LEBENSBLÜTE (Überheilung, löscht Brennen) |
| **Brennglas** (`gem_lens_1..5`) | Licht | Brand +15..60 %; III Schein +15 %, V NACHBRAND |
| **Wildwuchs** (`gem_wild_1..5`) | Wurzel | Dauer +15..60 %; III Kreis +15 %, V BLÜTENSCHLUSS |

- **Stab** `staff_hag_elm` (Hexenulmenstab): Hotbar-Werkzeug (`tool: "staff"`), 1 Zauber- + 1 Verstärkerfassung, alle Stufen. Kurz und kräftig: gedrehte Hexenulme, Fluchsilber-Band, Silberfassung für den Verstärker, Zweigkorb für den Kristall (`tools/art_weapons.py` `staff`).
- **Einsetzen:** Stein auf dem Cursor auf den Stab klicken (der alte kommt zurück), Rechtsklick auf den Stab nimmt den Zauberkristall, dann den Verstärker heraus (`InventoryComponent._socket/_unsocket`, Extras `sp`/`gm`, auch in Drops `ItemDrop.sockets`). Ein eingesetzter Kristall beginnt leer.
- **Zaubern:** LMT mit dem Stab (`Player.begin_cast`, Sheet 18 `player_cast.png` aus `py -3 tools/art_hero_cast.py`: LICHT hochreißen und kniend in den Boden stoßen, WURZEL ausholen und nach vorn fegen). `SpellComponent` (Host: Ladung, Prüfung, `_rpc_zone`), `SpellRules` (rein), `data/spells.json`. Nur ein schwerer Treffer bricht das Zaubern ab (wie Trinken).
- **Zonen:** `SpellZone` → `BanishLight` (Shader `magic_light_ground`, `magic_light_curtain`) und `RootGround` (`magic_root_soil`, `magic_root_glow`, einzelne y-sortierte `MagicRoot`). Jeder Peer zeichnet, nur der Host schadet/heilt.
- **Kunst:** `py -3 tools/art_crystals.py` (Icons, 32er-Karten, `staff_stones.png`, Kontaktbogen `docs/img/crystals.png`), `StaffCrystals` zeichnet die Steine eingefasst in den Stab und ins Inventar-Icon. Ton: `py -3 tools/audio_magic.py` (Platzhalter).
- **Dev:** ENTWICKLER → ZAUBERSTAB + ALLE KRISTALLE. Test `tools/test_magic.tscn` (144 Prüfungen, `MAGIC OK`), Look-Studie `tools/preview_magic.tscn -- --dir=/abs [--tier=N]` (`--rendering-driver opengl3`).
- **Nicht gebaut:** Quellen (Loot, Mine, Seehexe), Ladering am Hotbar-Slot, späte Beitreter sehen laufende Zonen nicht, Wachstum der Kristalle.

## 15. Gebaut (2026-11-11): ein Zauber für Glut, Nebel und Leere

Je ein Zauberkristall in fünf Stufen (15 Steine), noch keine Verstärker dafür. Die Ideen des Nutzers sind die Grundlage, aufgewertet wie unten beschrieben.

| Zauber | Schule | Wirkung | III | V |
|---|---|---|---|---|
| **Glutschwarm** (`crystal_embers_1..5`) | Glut `#ff9a42` | 1/2/3/4/5 brennende Splitter lösen sich aus dem Kristall, hängen kurz im Fächer um die Krone und fliegen in eigenen Bögen auf die Schattenwesen in Reichweite (140..180 px), **das dem Zeiger nächste zuerst**, einer pro Gegner. Weniger Gegner als Splitter: sie bündeln sich, **jeder weitere Splitter auf dasselbe Ziel trifft x1,5** (Auslegung von „1,5 multipliziert je“). Treffer 9..20, dann **Brand** 3..7/s für 4..6 s; ein Splitter auf ein brennendes Ziel verlängert um 1 s. **Ohne Gegner passiert nichts**: kein Zauber, Hinweis KEIN ZIEL, der Kristall bleibt voll. Laden 9..7,5 s. | FUNKENSPRUNG: stirbt ein Brennendes, springt sein Feuer auf das nächste in 64 px | GLUTHERZ: der letzte Splitter zerbirst in einem Glutring (30 px, halber Schaden + Brand) |
| **Nebelschleier** (`crystal_veil_1..5`) | Nebel `#b9aaff` | Ziel ist der Spieler unter dem Zeiger (Füße bis Kopf zählen, 170 px Reichweite), sonst Ellie selbst. Ein Nebelband rollt vom Kristall zum Ziel und schließt sich um ihn. 4..8,5 s **vernebelt** (Status `veil`): halb durchsichtig mit wandernden Nebellöchern, rutschenden Pixelzeilen, Glitch-Balken und Schwaden (für die anderen nur ein Flackern, für sich selbst noch lesbar). **Schattenwesen können ihn weder anvisieren noch behalten**: wer ihn jagt, verliert ihn, läuft zur letzten bekannten Stelle und sucht dort. Flächen- und schon geworfene Angriffe treffen weiter. Laden 30..22 s. | IRRSPUR: wo der Schleier fällt, bleibt ein Trugbild aus Nebel 3 s stehen, genau dort suchen die Jäger | SCHLEIERKREIS: der Nebel legt sich auch über jeden Spieler in 40 px um das Ziel |
| **Leerenschlund** (`crystal_maw_1..5`) | Leere `#d27bff` | Die Leere nimmt immer einen Preis: **10..7 % des maximalen Lebens** sofort (nie der letzte Punkt; zu wenig Leben = ZU WENIG LEBEN, kein Zauber). An der gezielten Stelle (130 px) reißt der Boden zur Leere auf: schwarzes Loch mit zerrissener Lippe, Spiralarme aus violettem Licht, Sterne im Schwarz. 2,2..3,1 s **saugt** es alle Schattenwesen im Kreis (44..62 px) zur Mitte (48..74 px/s, Wände halten, Wesen ab 300 Leben sind zu schwer), Fäden der Leere greifen nach ihnen. Dann **schnappt es zu**: 18..50 Schaden (am Rand 60 %), weißer Saum, Ring, Splitter, Kamerastoß, und für jedes gebissene Wesen fließen **4..6 % ihres Lebens zurück** (ein Strom violetten Lichts zu ihr). Viele Gegner = Gewinn, keiner = reiner Preis. Laden 16..12 s. | SATTER SCHLUND: frisst er 3+ Wesen, lädt der Kristall den Rest doppelt so schnell | LEERER STERN: unter 20 % Leben wird ein Wesen ganz verschlungen und gibt doppelt zurück |

- **Zielhilfe** (`SpellAim`, nur auf dem eigenen Bildschirm, gedimmt solange der Kristall lädt): Glut zeigt über jedem Ziel eine kleine Flamme und einen Glutpunkt pro Splitter, Nebel einen Ring unter dem Spieler, der vernebelt würde, Leere den Sogkreis, Wurzelgrund seinen Kreis.
- **Animationen** (`tools/art_hero_cast.py`, Sheet 18 jetzt 5 Clips x 12 Frames): GLUT spannen wie ein Bogen (Stab über die Schulter, linke Hand zeigt aufs Ziel) und vorschnellen; NEBEL Stab aufrecht, linke Hand zieht wie ein Schleier über das Gesicht und öffnet sich zum Ziel; LEERE aufbäumen, die linke Hand krallt nach oben ins Dunkel, dann tief in die Hocke und die Krone in den Boden. Stabhaltung in `Player.STAFF_KEYS`.
- **Technik:** `SpellComponent` prüft je Art (Ziele, Spieler-Wahl, Preis) beim Besitzer und auf dem Host noch einmal; `_rpc_zone(.., extra)` trägt die Entscheidung des Hosts (Splitter-Ziele als Knotenpfade + Faktor, die Vernebelten, den gezahlten Preis). Knoten: `EmberVolley` + `EmberBurn` (Brand als Kind des Gegners, nur der Host tickt, `_rpc_burn_jump` für FUNKENSPRUNG), `VeilStream` (der Wurf) + Status `veil` in data/status_effects.json + `VeilFx` (Shader `hit_flash.gdshader` `veil`/`veil_keep`/`veil_seed`) + `VeilGhost`, `VoidMaw` (Shader `magic_void_maw.gdshader`). `Player.veiled()` wird von Spinne, Lauscher, Brecher und Lichtfischer gefragt (Zielwahl, Zielbehalt, Rückangriff auf den letzten Angreifer).
- **Kunst/Ton:** `py -3 tools/art_crystals.py` (drei neue Rampen und Zeichen: Flamme, verschleiertes Auge, Schlund mit Zähnen; Spalten 4-6 in `staff_stones.png`), `py -3 tools/audio_magic.py` (13 neue Platzhalter).
- **Nicht gebaut:** Brand auf Gegnern ist kein allgemeiner Statuseffekt (nur Glutschwarm nutzt ihn). Verstärker und Bosse: Abschnitt 16.

## 16. Gebaut (2026-11-11): Verstärker für Glut, Nebel, Leere und der Schleier gegen Bosse

### 16.1 Drei neue Verstärkerfamilien

Gleiche Form wie Brennglas und Wildwuchs (rund, milchig, geschliffen, das Zeichen eingeschnitten), getönt in der Farbe ihrer Schule. Jeder Stein verstärkt, was seine Schule ausmacht, und passt nur zu ihr.

| Stein | Familie / passt zu | I..V | III | V |
|---|---|---|---|---|
| **Zunder** (`gem_tinder_1..5`, Zeichen: Flamme) | ZUNDER / Glut | Brand +15..60 % (Schaden pro Sekunde **und** Dauer) | FUNKENFLUG: ein Splitter mehr | AUFLODERN: ein Splitter auf ein Wesen, das schon brennt, trifft doppelt (Feuersäule, eigener Klang) |
| **Dunst** (`gem_haze_1..5`, Zeichen: Schwaden) | DUNST / Nebel | Schleier +15..60 % länger | FLÜCHTIG: der Kristall lädt 15 % schneller | NEBELWAND: wo der Schleier fällt, bleibt eine Nebelwolke (34 px) liegen, solange er hält und 4 s länger; wer darin steht, bleibt vernebelt. Ein Rückzugsort für die Gruppe |
| **Hunger** (`gem_hunger_1..5`, Zeichen: Schlund mit Zähnen) | HUNGER / Leere | Rückfluss +15..60 % | WEITER SCHLUND: Sog 15 % weiter | ZWEITER BISS: 0,5 s nach dem ersten schnappt der Schlund noch einmal zu (halber Biss, halber Rückfluss) |

Technik: `data/spells.json` `gems` (`burn_up`, `shard3`, `rekindle`, `quick3`, `cloud`/`cloud_radius`, `refund_up`, `radius3`, `bite2`), angewandt in `SpellRules.params`; AUFLODERN in `EmberVolley._impact`, NEBELWAND in `VeilStream` (Host frischt `veil` alle 0,5 s für 1 s auf), ZWEITER BISS in `VoidMaw._snap(share)`. Kunst `py -3 tools/art_crystals.py` (Spalten 7-9 in `staff_stones.png`).

### 16.2 Der Schleier gegen Bosse

Mornath und Morwenna führen jetzt zwei Listen: `_living()` (lebend und in der Nähe) bleibt für alles, was die ganze Gruppe betrifft: das Zurücksetzen des Kampfes, wenn niemand mehr da ist, die Skalierung nach Spielerzahl, Druckwellen, die Wahl der Säule. Neu ist `_seen()` (lebend, nah, **nicht vernebelt**) für alles, was zielt: die Zielwahl (`_pick_target`), das Festlegen des Zielpunkts, Sturzflug und Jagd (verlieren sie ihr Ziel, nehmen sie ein anderes sichtbares oder schlagen dort ein, wohin sie gerade flogen), Splitter-Säulen, das Brandmal (die Feder findet niemanden), bei Morwenna Klone, Lanzen, Ausfälle, Tauchen, Karussell, Grabung und Tausch-Schnitt (`_by_seen`). Mornath sucht vernebelte Spieler auch nicht mehr mit dem Blick.

Folge: ist **jeder** vernebelt, findet der Boss niemanden. Zielangriffe fallen aus (kurze Pause), Flächenangriffe (Regen, Wellen, Wurzelschach) laufen weiter. Der Kampf setzt sich dadurch **nicht** zurück, weil das Zurücksetzen weiter an `_living()` hängt. Tests: `tools/test_boss_fight.tscn` und `tools/test_witch_boss.tscn` prüfen Verlieren und Wiederfinden.

## 17. Gebaut (2026-11-11): die Bleichgabel, der erste Stab mit zwei Zinken

**Idee:** ein Ast des Bleichbaums, der sich oben zu einem schmalen, ungleichen Y spaltet, so wie er gewachsen ist. Die obere Zinke läuft länger weiter, die untere bricht früher ab. Gebleichtes, knochenweißes Holz mit dunkelvioletten Rissen, ein Knöchelknauf am Fuß, Lederwicklung am Griff, ein Fluchsilberband unter der Gabelung und im Schritt der Gabel ein glühender **Schattenkern**. Jede Zinke trägt eine Silberfassung für ihren Verstärker und endet in einer Klaue aus zwei Knochenfingern, die den Zauberkristall halten (die Klauen sind klein: die Gabel trägt eigene kleine Steine, 5x7 px Kristalle und 3x3 px Perlen, `assets/magic/staff_stones_small.png`, `small_stones` im Stab-Eintrag) (`tools/art_weapons.py` `bone_fork`, `staff_bone_fork` in data/items.json, selten).

| | |
|---|---|
| **Zinken** | 2 Zinken mit je einem Zauberkristall und einem Verstärker (`sp`/`gm` und `sp2`/`gm2` am Stapel). Der Verstärker wirkt nur auf den Kristall seiner Zinke. Höchste Stufe V. |
| **Bedienung** | **Linksklick** wirkt die lange Zinke, **Rechtsklick** die kurze. Jede Zinke lädt für sich (eigene Ladung, eigenes Aufblitzen). Die Zielhilfe zeigt beide, die rechte etwas blasser. |
| **Einsetzen** | Stein auf die **obere Hälfte** des Stab-Bilds legen: lange Zinke, auf die **untere Hälfte**: kurze Zinke (die Diagonale des Icons trennt sie). Ohne klare Hälfte nimmt die erste freie Zinke den Stein. Rechtsklick nimmt aus der Zinke unter dem Zeiger heraus (erst den Kristall, dann den Verstärker). |
| **GABELSCHLAG** | Wirkst du die andere Zinke binnen **3 s** nach der ersten, kommt ihr Zauber **x1,25** heraus (Schaden, Brand, Heilung, Rückfluss; Schleier, Licht und Wurzeln halten etwas länger). Ein Blitz springt zwischen den Kristallen, die Gabel singt (`fork_strike`), über Ellie steht GABELSCHLAG. Danach braucht es ein frisches Paar. |
| **GLEICHKLANG** | Zwei Kristalle **derselben Schule**: beide laden **15 % schneller**. Am Stab hängt ein ruhiger, pulsierender Lichtfaden zwischen ihnen. |
| **ZWIESPALT** | Zwei Kristalle **gegensätzlicher Schulen** (Licht↔Leere, Natur↔Glut, Licht↔Nebel, `opposites` in data/spells.json): beide laden **10 % langsamer**, dafür trifft der Gabelschlag mit **x1,5**. Zwischen den Kristallen knistern Funken. |
| **Herkunft** | Ilva baut sie im Reiter STÄBE (`recipes.json` `staff_bone_fork`: 6 Bleichholz, 3 Fluchsilber, 2 Seemondstein, 1 Schattenkern, Vertrauen 30). Dev: ENTWICKLER → ZAUBERSTÄBE + ALLE KRISTALLE. |

Kombinationen, die sich lohnen: Wurzelgrund + Bannlicht (heilen, dann schützen), Glutschwarm + Leerenschlund (Zwiespalt: anzünden, dann ein Gabel-Biss x1,5), Nebelschleier + Nebelschleier (Gleichklang: zwei Leute nacheinander verstecken).

**Technik:** `SpellRules` (`spell_key/gem_key(prong)`, `SOCKET_KEYS`, `prongs_of`, `staff_def`, `fork_bond`, `fork_rules`, `empower`), `data/spells.json` `staffs` (je Stab `crowns`/`knots` = [entlang, quer] px im gehaltenen Bild, `icon_crowns`/`icon_knots` im 16er-Icon, `fork`), `InventoryComponent._socket/_unsocket(staff, prong)` (Klick-Argument 3 = Zinke, `ItemSlot._prong_at`), `SpellComponent` mit zwei Zinken (`spell_of/gem_of/charge_fraction/is_ready/cast_params/try_cast(.., prong)`, `fork_struck`, die alten Namen `spell`/`gem`/`charge_left` sind Zinke 0), die Zinke reist im Aktionsnamen mit (`cast_light@1`, `Player.cast_prong`), `AttackComponent.item_point`, `StaffCrystals` (Plätze aus den Daten, Faden, Funken, Blitz). Test `tools/test_magic.tscn` (364 Prüfungen), Ansicht `tools/preview_magic.tscn -- --dir=/abs --fork`.
