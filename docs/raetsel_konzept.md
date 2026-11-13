# Prüfungen der Wächterin – Rätsel in der Welt (Konzept, 2026-11-12)

Kleine Rätsel, über die man beim Erkunden stolpert und die mit einer Truhe aus dem Licht belohnen (wie Genshins Siegel- und Zeiträtsel). Dieses Dokument ist **Konzept, nichts davon ist gebaut**. Die Truhen selbst und ihre Ankunft aus der Lichtsäule gibt es schon (`docs/beutetruhen_konzept.md`, `LootChests`, `LootChest.arrive`).

Ausgearbeitet: **Irrlichtspur**, **Runenreihe**, **Schweigender Hain**, **Krähenschatz** (gewöhnlich + selten), zwei neue, **Rissläufer** und **Die letzte Laterne**, **Das Wurzelgeflecht** (6a) und der **Sternenspiegel** (6b). Am Ende stehen das gemeinsame Designkonzept, Technik und Bauplan.

---

## 0. Die Idee dahinter

**Lore:** Die Göttin der Wegsteine (die „Wächterin“, `hang_wachterin`) hat vor dem Einbruch der Leere Prüfungen im Land hinterlassen: Orte, an denen sie Vorräte für die verwahrte, die aufmerksam, geduldig und mutig sind. Jede Prüfung hat einen **Prüfstein**, der ihren Zustand zeigt. Wer sie besteht, dem schickt die Wächterin eine Truhe in ihrem Licht. Dadurch passen alle Rätsel in eine gemeinsame Bildsprache, und die Belohnung (Lichtsäule) erklärt sich von selbst.

**Vier Regeln für jedes Rätsel**
1. **Lesbar ohne Text.** Fortschritt sieht und hört man (Teal = Fortschritt, Gold = gelöst, ein violetter Puls = zurückgesetzt). Texte gibt es höchstens als ein Satz von Ellie.
2. **Scheitern tut nicht weh.** Ein Fehlversuch setzt zurück, mit Ausnahme der beiden Kampfrätsel (Hain, Laterne) kostet er kein Leben, und es geht nie etwas verloren.
3. **Jedes Rätsel spielt mit einem System, das es schon gibt**: Schleichen, Tag und Nacht, Schattenschritt, Krähen, Licht ist Land. Rätsel sollen das Spiel lehren und belohnen, nicht neue Regeln erfinden.
4. **Koop macht es leichter oder schöner, ist aber nie Pflicht.** Host-autoritativ, jeder Spieler kann Fortschritt machen, die Truhe gehört allen.

---

## 1. Irrlichtspur (gewöhnlich)

> **Gebaut (2026-11-12), erste Fassung:** `WispTrail` (src/entities/puzzles/wisp_trail.gd) + `Puzzles` (src/world/puzzles.gd, Knoten von `WorldLevel`, Speicherschlüssel `puzzles`), Daten `data/puzzles.json` (Tuning `wisp`, `placed`: Schale, Route in Tiles, `stops`, `linger`). Erste Spur `wisp_nordweg`: Schale bei Tile (796, 647) nördlich der Hütte, die Route (~106 Tiles, geprüft auf flachem Level-0-Land, fern von Wasser und Leere) läuft am Ostfuß des Plateaus nach Norden, durch den Pass an der Leere entlang und endet versteckt hinter dem Hügel bei (839, 588). Abweichungen vom Konzept: Die Schale (Steinsäule mit Moosbett, `py -3 tools/art_wisp.py`) ersetzt den Blütenfleck; das Irrlicht ist **zu jeder Tageszeit** da (Abendfenster noch nicht gebaut); es fliegt in Sprüngen von Haltepunkt zu Haltepunkt auf einer Catmull-Rom-Kurve (leicht schneller als ihr Gehen, 68 px/s, beim Schleichen 46 px/s, immer langsamer als ihr Sprint), Erschrecken = zum nächsten Haltepunkt mit 1,4-fachem Tempo, nie auf den letzten; nach dem Verlöschen ist es 7 s später wieder in der Schale. Ende: Spirale, Sturz, Lichtrisse, Ring aus Leuchtblumen, Wurzelkiste aus der Lichtsäule (`LootChests.appear`, Id `trial_<id>`); wie jede Truhe verschwindet sie 10 s nach dem Öffnen für immer (`fade_after`). Klänge `py -3 tools/audio_wisp.py`. Dev: ENTWICKLER -> IRRLICHT: ZUR SCHALE / IRRLICHT ZURÜCKSETZEN. Test `tools/test_wisp.tscn` (`--fixed-fps 60`, `WISP OK`), Look `tools/preview_wisp.tscn -- --dir=/abs [--night]`. Noch nicht: Irrlichtsud-Synergie, Nebelspur, Karte, Prüfstein, Pflanzen/Glühwürmchen unterwegs, Netzwerktest.

**Fantasie:** In der Dämmerung löst sich ein Irrlicht aus einem Fleck Leuchtblüten und will dir etwas zeigen, aber es ist scheu.

**Ort:** an einem Fleck Leuchtflora (Moonbell, Glühfarn, Glow Caps) am Waldrand. Die Spur führt 50–90 Tiles weit über flachen Boden, an etwas Schönem vorbei (Wasserfall, Lichtung, Aussicht), und endet an einer versteckten Stelle (hinter einem Felsen, unter einer Weide).

**Ablauf**
1. Von der Dämmerung bis zur Mitte der Nacht (`TimeManager`: ab `golden_amount` > 0,5 abends bis 0,92) schwebt über dem Blütenfleck ein faustgroßes Irrlicht und kreist langsam. Am Tag ist dort nur ein leiser Schimmer in den Blüten, ein Hinweis für Aufmerksame.
2. Kommt Ellie auf 90 px heran, „schaut“ es sie an (es zuckt in ihre Richtung) und schwebt zum ersten Wegpunkt.
3. Es folgt einer festen Route aus 8–14 Wegpunkten (Daten). Dabei gilt der Abstand zu ihr:
   - **< 36 px oder Sprint/Schwerthieb im Umkreis von 70 px:** es erschrickt (violettes Flackern, ein hohes Zirpen), schießt zwei Wegpunkte voraus, **Scheu +1**.
   - **36–120 px:** es schwebt weiter (Tempo = ihr Gehtempo × 0,85), es zieht eine Spur aus Teal-Funken, die 4 s am Boden liegen bleibt.
   - **> 150 px:** es wartet, pulsiert heller und „ruft“ (ein Glockenton, der lauter wird).
   - **> 300 px für 8 s, oder Scheu 3:** es verlischt, Rücksetzen. Am nächsten Abend ist es wieder da.
4. **Schleichen** beruhigt es: Ellie darf dann bis auf 20 px heran, und das Irrlicht ist schneller (×1,15). Das ist die Lektion: leise folgen.
5. Am Ende sinkt es in den Boden. Kreisförmig erblühen kleine Leuchtblumen, dann fällt die Wurzelkiste aus der Lichtsäule.

**Unterwegs:** Wo es vorbeischwebt, leuchten kurz Pflanzen auf, und Glühwürmchen folgen ihm. Einmal pro Route macht es an einer Stelle Halt und kreist um etwas (ein Glow Cap, eine Kristallader): ein kleiner Bonus und Hinweis „schau hier“.

**Synergie:** Mit dem **Irrlichtsud** (`wisp`, `NightBehavior._wisp_say`) im Blut ist es zutraulich: Scheu-Grenze 5, und es zeigt am Ende eine zweite, kleinere Stelle (+1 Ziehung aus `wild_uncommon`).

**Koop:** Es achtet auf den nächsten Spieler. Ein sprintender Mitspieler erschreckt es trotzdem, also müssen alle leise sein.

**Varianten:** *Nebelspur* (selten, Hexenwald): Im Halluzinationsnebel tauchen zwei falsche Irrlichter auf, die zu nichts führen. Das echte wirft als einziges Licht auf den Boden (`NightLight`), die falschen nicht.

**Design**
- Irrlicht: ein 5×5-Pixel-Kern mit Halo, Unlit, Teal-Weiß, das Herz pulsiert im Atemtakt, dazu 2–3 kreisende Funken. Sein Zustand zeigt sich in der Farbe: Teal = ruhig, Gold = zufrieden (am Ziel), Violett = erschrocken.
- Spur: Teal-Pixel, die liegen bleiben und verblassen (wie `ShadowPatch`, nur hell). Ziel: ein Ring aufblühender Leuchtblüten (`MeadowDetails`-Varianten).
- Klang: drei aufsteigende Glasnoten beim Losfliegen, ein Zirpen beim Erschrecken, ein Ruf-Ton beim Warten.

---

## 2. Runenreihe (selten)

**Fantasie:** Fünf alte Runensteine im Kreis und in der Mitte eine Sonnenuhr. Die Reihenfolge, in der man die Steine berühren muss, steht nirgends. Die Zeit verrät sie.

**Ort:** eine kleine Steinsetzung auf einem Plateau oder einer Lichtung. Zwei der fünf Stelen stehen erhöht oder hinter einem Hang, damit Laufwege dazugehören.

**Die zwei Hinweise (immer beide da)**
- **Am Tag: die Sonnenuhr.** Der mittlere Prüfstein ist eine Sonnenuhr mit einem schrägen Stab. Ihr Schatten wird von der Node selbst gezeichnet (die Welt hat keinen echten Sonnenstand): Er dreht sich mit der Uhrzeit von West über Nord nach Ost. Auf dem Ring der Uhr sind fünf Kerben mit den Runen der fünf Stelen eingeritzt. **Die Reihenfolge, in der der Schatten im Lauf des Tages über die Kerben wandert, ist die Lösung.** Wer kurz wartet (ein Tag dauert 8 Minuten), sieht ihn wandern. Wer schlau ist, liest die Reihenfolge einfach im Uhrzeigersinn vom Schatten ab.
- **In der Nacht: Mondschrift.** Bei Mondlicht (`TimeManager.moon_light()` > 0,3) glühen die Kerben nacheinander auf (Glow-Schicht, 1,2 s Abstand, dann eine Pause), in der gleichen Reihenfolge. **Bei Neumond bleibt die Schrift dunkel**: Dann gilt nur noch der Schatten, den es nachts nicht gibt. Eine kleine Gemeinheit, die man über Mondphasen lernt.

**Ablauf**
1. E an einer Stele: Ellie legt beide Hände auf (`Player.begin_touch`). Ist sie richtig, leuchtet ihre Rune Teal, ein Lichtfaden läuft über den Boden zur Sonnenuhr, und ein Ton erklingt (jede Stele hat ihre Tonhöhe, zusammen ergeben sie eine Melodie).
2. Falsch: Alle Stelen flackern violett, die Fäden reißen, ein absteigender Ton, zurück auf null. Kein Schaden.
3. Alle fünf richtig: Die Sonnenuhr dreht sich einmal ganz um (der Schatten schlägt einen Kreis), ein goldener Ring läuft über alle Fäden, dann kommt die Mondsiegeltruhe.

**Koop:** Ein zweiter Spieler kann an der Sonnenuhr stehen und ansagen. Optional: Berühren zwei Spieler zwei aufeinanderfolgende Stelen innerhalb von 1 s, gibt es einen Doppelton (nur Kosmetik).

**Varianten:** *Drei Stelen* (gewöhnlich, Anfangsgebiet). *Gespiegelt* (Hexenwald): Die Schatten fallen dort falsch herum, gezählt wird gegen den Uhrzeigersinn. Ellie bemerkt es in einem Satz, sobald man einmal falsch lag.

**Design**
- Stelen aus dem hellvioletten Stein der Wegstatuen mit Teal-Einlage und einer der sechs **Prüfrunen** (Abschnitt 7): Mond, Wurzel, Auge, Flamme, Welle, Feder. Moos und Risse wie bei den schlafenden Wegsteinen.
- Sonnenuhr: eine flache runde Platte auf einem Sockel, ein schräger Bronzestab mit einem Federknauf, ein Schatten aus 1–2 px Breite in Bayer-Dithering, der mit der Zeit länger und kürzer wird (mittags kurz).
- Fäden: Pixellinien am Boden, Teal, die „hineinwachsen“ (wie die Lichtwelle der Wegsteine).

---

## 3. Schweigender Hain (selten)

**Fantasie:** Mitten in einem dunklen Wäldchen steht eine Truhe zwischen schlafenden Schattenspinnen. Wer schleicht, kommt durch, wer laut ist, weckt den Hain. Die Rückkehr der ersten Lektion des Spiels (die Wächterspinnen am Pfad), diesmal als Belohnung.

**Ort:** ein dichter Hain (Woods, `DENSE_CROWN_OVERLAP`) mit tiefem Schatten. Die Spinnen sind Tagesreste, die im Schatten der Kronen schlafen (wie es das Nachtsystem schon kennt: „schwache Reste im Schatten der Bäume am Tag“). **Das Rätsel gibt es nur am Tag.** Nachts ist der Hain wach und gefährlich, und die Truhe ist im Schatten versunken (nur ein violetter Schimmer am Boden).

**Aufbau**
- 4–7 schlafende Spinnen (`shadow_spider` mit neuem Zustand `SLEEP`: eingerollt, Beine untergeschlagen, Augen zu, langsames Atmen der Glow-Schicht), auf festen Plätzen um die Truhe. Ihre „Schlafkreise“ überlappen so, dass es 1–2 Schleichwege gibt.
- **Knackzweige**: 10–20 trockene Zweige auf dem Boden (neues kleines Prop, sichtbar, nicht versteckt). Wer darüber läuft, macht ein Knacken (Lärm). Wer schleicht, bricht sie nicht. Wer gegen den Weg läuft, wird bestraft.
- Gefallene Blätter (eine Bodenfläche `dry_leaves`, Fußspur raschelt): Gehen ist laut, Schleichen leise.

**Regeln: der Weck-Zeiger**
- Jede Spinne hat einen unsichtbaren Schlafwert 0–100. Lärm in ihrer Nähe erhöht ihn: Gehen +6/s innerhalb 90 px, Sprinten +30/s innerhalb 150 px, Knackzweig +40, Schwerthieb +50, Schattenschritt +15. Schleichen erhöht ihn nur innerhalb 40 px (+8/s). Ohne Lärm sinkt er um 10/s.
- **Lesbar:** ab 40 zuckt ein Bein, ab 70 öffnet sich ein Auge (ein einzelner Magenta-Pixel, ein leises Zischen), ab 100 ist sie wach.
- **Wach:** Die Spinne kreischt, alle anderen im Umkreis von 120 px +50. Die Truhe versinkt in einer Schattenlache (der Deckel wird zuerst verschluckt, dann der Rest, 1,2 s). Die wachen Spinnen kämpfen normal (normale Werte, **nicht** die 400 Schaden der Wächter).
- Sind alle wachen Spinnen tot, kehrt Ruhe ein. Nach 90 s (oder am nächsten Tag) taucht die Truhe wieder auf und neue Spinnen schlafen auf den leeren Plätzen. Wer kämpfen will, kann das, bekommt aber keine Truhe dafür.
- **Erreicht Ellie die Truhe**, öffnet sie sie wie jede Mondsiegeltruhe (E halten 0,9 s; das Halten ist leise). Beim Aufspringen der Truhe wachen alle Spinnen auf. Wer sie fliehen lässt (Schattenschritt hinaus), gewinnt; wer bleibt, muss kämpfen. Die Beute liegt schon draußen.

**Koop:** Jeder Spieler macht Lärm, alle müssen leise sein. Ein Mitspieler kann absichtlich am Rand Lärm machen, um Spinnen abzulenken (Lärm erzeugt einen „Blickreiz“: eine fast wache Spinne dreht sich zur Lärmquelle, ein Ablenkmanöver).

**Varianten:** *Lauscherhain*: Unter den Spinnen schläft ein Lauscher, der auf größere Entfernung hört (×1,6), dafür langsamer wach wird.

**Design**
- Schlafende Spinne: neue Pose in `SpiderRig` (Beine eingezogen, Körper flach), Glow-Schicht atmet sehr langsam, die Augen sind dunkel. Ein Auge, das sich öffnet, ist ein einzelnes Magenta-Pixel, das hochglimmt.
- Die Truhe steht auf einem Moosflecken in einem Lichtfleck (ein einziger Sonnenstrahl durch das Kronendach, `DaylightField`), also der einzige helle Ort im Hain: man sieht das Ziel sofort.
- Knackzweige: drei Varianten 12×6 px, hellgraues Totholz, gut lesbar auf dunklem Waldboden.
- Ton: Der Hain ist still (die Umgebungsgeräusche werden leiser), man hört das Atmen der Spinnen. Je näher eine am Aufwachen ist, desto lauter und unregelmäßiger.

---

## 4. Krähenschatz (gewöhnlich und selten)

**Fantasie:** Krähen sammeln Glitzerzeug und verstecken es. Wer sich mit ihnen gutstellt, dem zeigen sie ihr Versteck.

**Gewöhnlich: die Hortkrähe**

> **Gebaut (2026-11-12):** `CrowHoard` (src/entities/puzzles/crow_hoard.gd, ein `WorldTrial` wie die Irrlichtspur; `Puzzles` verwaltet beide), Daten `data/puzzles.json` (`crow`-Tuning, Eintrag `hoard_flussufer`: Stumpf bei Tile (826, 701) östlich vom Fluss, Erdhaufen bei (857, 709) hinter einem kleinen Hügel). Eine eigene, beringte Krähe (Sheet der Wildvögel, nicht aus dem Schwarm); Anlocken: geliebtes oder gemochtes Futter in der Hand, nah (115 px), still stehen oder langsam schleichen; Sprint, Schlag, Heranstürmen oder zu nah = sie fliegt zurück (5 s Pause). Füttern mit Ellies Fütter-Clip (`begin_feed`), ein Futter wird verbraucht, dann fressen, zweimal krächzen, Bogenflug zum Haufen, kratzen, bis jemand auf 52 px herankommt, Heimflug. Graben: E „AUSGRABEN“ (Ellie gräbt mit den Händen, Pflück-Clip), alternativ drei Hackenschläge (`HarvestHurtbox`). Kamerawackeln beim Ausbruch bewusst sanft. Die Wurzelkiste bricht aus der Erde (`LootChest.rise`: Boden bebt und wölbt sich, Risse, Ausbruch mit Erdbrocken und Steinen, die Truhe schießt aus dem Loch (Shader schneidet sie an der Bodenlinie ab), springt, kracht herunter und steht in aufgerissener Erde). Hortplatz in vier Varianten (`py -3 tools/art_hoard.py`: Blitzstumpf, Ringstumpf, schiefer Stumpf mit Ast, kleiner Fels; `variant` im Eintrag). Gespeichert wird auch ein gezeigter, noch nicht ausgegrabener Hort. Dev: ENTWICKLER -> HORTKRÄHE: ZUM BAUM / ZURÜCKSETZEN / SONNENKERNE + HACKE. Test `tools/test_crow_hoard.tscn` (`CROW HOARD OK`), Look `tools/preview_crow_hoard.tscn -- --dir=/abs [--night]`, Bild `docs/img/crow_hoard.png`. Noch nicht: Pet-Bindungspunkte, Unterbrechung durch Waffentreffer (Schläge scheuchen sie nur), Rabenhandel.
- **Ort:** ein auffälliger Baum oder Felsen, auf dem eine einzelne Krähe sitzt, umgeben von kleinen Glitzerpunkten im Gras (Glasscherben, ein Knopf: Kosmetik). Die Krähe hat einen kleinen Silberring am Bein (Kennzeichen „Hortkrähe“, wie die Pet-Ringe).
- **Ablauf:** Wie beim Anlocken der Haustiere (`PetBehavior`): mit Lieblingsfutter in der Hand (`seed_fluff`, `sun_seed` = „loves“) schleichen und stillstehen. Die Krähe kommt, Ellie füttert sie (`PetFeedSpot`, `begin_feed`). Danach krächzt sie zweimal, fliegt in einer Kurve zu einer Stelle in 20–40 Tiles Entfernung und landet auf einem **Haufen frischer Erde** (ein neues Prop, nur sichtbar, solange das Rätsel offen ist). Sie pickt dort, bis Ellie kommt, dann fliegt sie zurück.
- **Graben:** Mit der **Hacke** (`hoe_basic`) auf den Erdhaufen schlagen, drei Schläge (`HarvestHurtbox`, `tool: "hoe"`). Jeder Schlag wirft Erde auf, beim dritten kommt die Wurzelkiste heraus. **Ausnahme zur Lichtsäule:** Diese Truhe kommt aus dem Boden (der Deckel bricht durch die Erde), denn es ist der Hort der Krähe, nicht die Gabe der Wächterin.
- Ohne Hacke: Ellie sagt „Ich brauche etwas zum Graben.“ Der Haufen bleibt.

**Selten: der Rabenhandel**

> **Gebaut (2026-11-12):** derselbe `CrowHoard` im Raben-Modus (Art `raven_trade`, `raven` true), Eintrag `raben_westhang`: Bleichbaum bei Tile (688, 641) westlich vom Fluss, Federstationen (667, 650), (676, 670), (651, 698) um einen Hügel herum, Hort bei (641, 713), Mondsiegeltruhe. Der Rabe kommt zu jedem, der still bei ihm steht. **Abweichung:** Glänzendes passt nicht in die Hotbar, deshalb öffnet „E ANBIETEN“ ein Tauschfenster mit einem Platz (`BoxWindow` + `ItemBox` „raven:<id>“); der Host prüft sofort, was hineingelegt wird (`raven.likes` in data/puzzles.json: Seeglimmer, Mondstein, Silberkette, Eisenbarren, Moras Splitter, Kristalle Stufe 1). Gefällt es ihm nicht: zurück in den Rucksack, er wendet den Kopf ab (dreimal am Tag = er ignoriert sie bis zum nächsten Morgen). Gefällt es ihm: ein Stück wird das Pfand, der Rest kommt zurück. Federn: schwarz mit Silberspitze, flattern herunter, E „FEDER AUFHEBEN“ (Pflück-Clip). Wartet er 60 s, fliegt er heim und führt beim nächsten Besuch an derselben Station weiter (statt wieder bei Station 1). Am Ende sitzt er auf dem Hort, E gräbt aus, die Truhe bricht aus der Erde, das Pfand liegt darin (`LootChests.add_extra`, gespeichert bis zum Öffnen). Dev: ENTWICKLER -> RABE: ZUM BAUM / ZURÜCKSETZEN / GLIMMER + STEIN FÜR DEN RABEN. Test `tools/test_raven_trade.tscn` (`RAVEN TRADE OK`), Look `tools/preview_crow_hoard.tscn -- --dir=/abs --raven`. Rabenplatz in drei Varianten (`py -3 tools/art_hoard_raven.py`: knorriger Bleichbaum mit langem Ast, Ring an der Kette und Schlüssel; Felsnadel mit Nest und kletternder toter Wurzel; Zwillingsstamm mit Nest in der Gabel; Bartflechten, gefallene Federn). Noch nicht: Nicken für zahlende Spieler, Pet-Bindungspunkte.
- **Ort:** ein toter Bleichbaum oder eine Felsnadel mit einem alten Raben (größer, ein Ring aus Rabenstahl).
- **Handel:** Raben wollen kein Futter, sondern **etwas Glänzendes**. Ellie bietet aus der Hand einen Gegenstand an (ein Rohstein wie `lake_glimmer`, `silver_chain`, ein Kristall Stufe 1). Der Rabe sieht ihn an: Gefällt er ihm nicht, wendet er den Kopf ab (Gegenstand bleibt). Gefällt er ihm, nimmt er ihn.
- **Die Kette:** Der Rabe fliegt los, aber nicht direkt. Er landet an **drei Zwischenstationen** und lässt dort jeweils eine **schwarze Feder mit Silberspitze** fallen (Unlit-Glanz, gut sichtbar). Ellie muss jede Feder aufheben (E), erst dann fliegt er weiter. Lässt sie sich zu lange Zeit (60 s), kehrt er zu seinem Baum zurück (zurück auf Station 1, die Feder bleibt gesammelt).
- **Das Versteck:** An der letzten Station sitzt er auf einem Erdhaufen zwischen Wurzeln. Graben mit der Hacke: Eine **Mondsiegeltruhe** kommt aus der Erde. **Der angebotene Gegenstand liegt mit darin** (der Rabe gibt sein Pfand zurück, plus seinen Hort).
- **Gedächtnis:** Der Rabe erinnert sich: Wer ihn betrogen hat (ein Gegenstand, der ihm nicht gefällt, wird dreimal angeboten), wird für den Tag ignoriert. Wer ihn bezahlt hat, dem nickt er künftig zu (Kosmetik, Verbindung zum Pet-System: +Bindungspunkte, wenn es dieser Vogel später werden soll).

**Regeln:** Es werden keine Tiere verletzt. Treffer mit Waffen schrecken die Vögel nur auf, wie bisher; dann ist das Rätsel für 60 s unterbrochen. Der Rabenstahl-Talisman (Rissfeder, `corvid_calm`) macht das Anlocken leichter, wie bei den Haustieren.

**Design**
- Hortkrähe und Rabe nutzen die vorhandenen Corvid-Sheets plus einen Ring-Overlay (`pet_marks.png`). Im Gras um ihren Baum liegen 4–6 Glitzerpixel, die bei Tag kurz aufblitzen (Sonnenglanz, `g_sun`).
- Erdhaufen: 24×14 px, frische dunkle Erde mit Krümeln, ein paar Federn und Krallenspuren, ein verbogener Löffel, der herausschaut.
- Rabenfedern: 8×8 px, schwarz mit Silberspitze, sie drehen sich langsam beim Liegen und funkeln.
- Graben: Erdklumpen fliegen (Partikel wie das Hacken auf dem Feld), beim dritten Schlag reißt der Boden auf und der Deckel bricht heraus (eigene kleine `arrive`-Variante `from_ground`).

---

## 5. NEU: Rissläufer (selten / legendär)

**Fantasie:** An einer Stelle, wo die Leere die Welt wund gemacht hat, hängen Risse in der Luft. Die Wächterin hat sie gebunden, aber nur jemand, der selbst durch die Leere schreiten kann, kann sie schließen. Das Rätsel ist eine Prüfung für **Ellies Schattenschritt**, die erste und einzige Fähigkeit des Leere-Zweigs.

**Ort:** eine „Narbe“: ein Fleck verbrannter, dunkler Boden mit Rissen wie am Weltrand (`void_edge`-Look in klein), oft auf einem Plateau oder zwischen Felsen. In der Mitte ein **Rissstein** (Prüfstein mit einer violetten Ader).

**Ablauf**
1. E am Rissstein: Ellie legt die Hand auf, die Narbe bebt. Um den Stein herum öffnen sich **5 Risse** in der Luft (gleicher Shader wie die Risse des Schattenschritts, `void_rift.gdshader`), jeder etwa 6×18 px, schwebend auf Hüfthöhe, mit einer Ausrichtung (manche quer, manche schräg).
2. **Einen Riss schließt man, indem man mit dem Schattenschritt durch ihn hindurchgeht.** Die gerade Linie des Schritts (`step_range` 54 px) muss die Risslinie kreuzen. Der Riss zieht sich mit einem Saug-Effekt zu und lässt einen Teal-Stern zurück.
3. **Reihenfolge:** Der nächste Riss pulsiert heller und ist von einer blinkenden Lippe umrandet, die anderen glimmen nur. Die Risse sind so gesetzt, dass ein Schritt aus dem vorigen Riss heraus den nächsten in Reichweite hat. Man plant eine Linie.
4. **Kette:** Zwischen zwei Schließungen bleiben **2,5 s** (der Schritt hat 0,8 s Abklingzeit). Bricht die Kette, reißen alle geschlossenen Risse wieder auf (violetter Puls, Glasbruch-Ton), zurück auf Anfang.
5. **Ausdauer** ist die eigentliche Herausforderung: Jeder Schritt kostet 14 + Stufe Ausdauer. Fünf Schritte in 10 s leeren die Leiste fast ganz. Wer zu viel läuft oder sprintet, schafft es nicht. Glutatem-Trank und Ausdauer-Stufen helfen spürbar.
6. Ist der letzte Riss zu, öffnet sich über dem Rissstein ein großer Riss, und **die Truhe fällt aus der Leere statt aus dem Licht**: ein schwarzer Spalt reißt auf, die Truhe stürzt mit violettem Nachglühen heraus, der Riss schließt sich mit einem tiefen Knall, und erst dann bricht goldenes Licht durch. Die Narbe heilt (der Boden wird grün, Gras wächst nach, dauerhaft gespeichert).

**Einseitige Risse (selten → legendär)**
- *Selten:* 5 Risse, alle von beiden Seiten passierbar.
- *Legendär:* 7 Risse, zwei davon **einseitig** (eine Lippe leuchtet, die andere ist dunkel; nur von der hellen Seite aus passierbar, sonst prallt Ellie ab und taumelt). Einer liegt über einer Kante, sodass man ihn nur erreicht, wenn man vom Plateau aus hinunter durchschreitet. Dazu ein **Wächterriss**, aus dem nach dem dritten Schließen eine Schattenspinne steigt: kämpfen oder Kette halten.

**Koop:** Mehrere Spieler können Risse schließen. Die Kette gilt für alle zusammen: Zwei Spieler können sich abwechseln und die Ausdauer teilen, das macht die legendäre Fassung zu zweit deutlich leichter.

**Lesbarkeit:** Der nächste Riss ist heller, die Ketten-Zeit zeigt sich als schrumpfender Teal-Ring am Rissstein (diegetisch, keine HUD-Leiste). Ein zartes Zielhilfe-Echo: Beim Zielen mit gedrückter Schritt-Taste (wenn es ein „Halten“ gibt) zeigt eine gepunktete Linie die Schrittbahn.

**Design**
- Risse: dieselbe Sprache wie Ellies Schattenschritt (Zickzack-Wunde aus Tinte, Fleisch aus Leere, eine Lippe von oben links beleuchtet, Adern), nur dass sie **dauerhaft** in der Luft hängen und langsam atmen. Jeder hat einen eigenen `seed` und `lean`.
- Narbe: Boden-Decal, dunkel und gerissen, mit violetten Glutlinien und Leere-Blüten. Nach dem Lösen: dieselbe Fläche als „geheilte Narbe“ mit jungem Gras und einer einzelnen Blüte in der Mitte.
- Klang: Risse brummen leise, beim Schließen ein Einsaugen und ein heller Ton, der mit jedem Riss höher wird (die Kette als Tonleiter). Abbruch: Glas, das rückwärts zerspringt.

---

## 6. NEU: Die letzte Laterne (legendär)

**Fantasie:** Alte Laternenschreine säumten früher einen Pilgerweg. Die Leere hat sie gelöscht, bis auf einen. In ihm schläft ein winziger **Laternengeist**, der nach Hause will, zum letzten Schrein am anderen Ende des Weges. Nachts, durch die Dunkelheit, in der die Schattenwesen wandern. Ellie muss ihn begleiten. **Das ist „Licht ist Land“ als Abenteuer**: ein wandernder Lichtkreis, den man durch die Nacht schützt.

**Ort:** ein vergessener Pilgerweg von 70–120 Tiles, gesäumt von 4–6 erloschenen **Laternenstöcken** (Steinsäulen mit einer leeren Laterne). Start: ein kleiner Schrein mit einem glimmenden Docht. Ziel: ein größerer Schrein mit einer Glocke. Der Weg ist ein gebackener Pfad (`data/ground.json` `paths`), zugewachsen.

**Ablauf**
1. **Nur nachts** (der Docht glimmt nur dann, tagsüber ist der Schrein kalt). E am Schrein: Ellie hält die Hände um den Docht (`begin_touch`), der Geist erwacht: ein Licht in Faustgröße mit zwei Punkten als Augen, er hüpft hoch, dreht sich um sie und wirft einen **Lichtkreis von 56 px** (ein echtes `NightLight` plus ein Kreis, den die Nachtwesen kennen).
2. **Er bewegt sich nur, wenn Ellie (oder ein Mitspieler) in seinem Lichtkreis steht**, langsam (65 % ihres Gehtempos), den Weg entlang. Verlässt sie den Kreis, bleibt er stehen und zittert.
3. **Licht ist Land:** Schattenwesen betreten seinen Kreis nicht (wie den der Stadt), aber sie **zehren am Rand**: Jede Kreatur, die die Kreisgrenze berührt, entzieht ihm Licht (der Kreis schrumpft, das Licht wird bläulich und flackert). Ellie muss am Rand kämpfen, sie zurückschlagen, aber im Kreis bleiben, sonst bleibt er stehen.
4. Die Nacht schickt Wellen: Sobald der Geist erwacht ist, ruft der Weg alle 25–40 s 2–4 Wesen aus der Dunkelheit (eigener kleiner Spawner mit dem Geburtsrecht aus `NightDirector`: Spinnen von Anfang an, nach dem zweiten Laternenstock auch Lauscher, die von außen **in den Kreis schießen** und ihn so schwächen, am Ende ein Brecher, der durch den Kreis rammt).
5. **Laternenstöcke:** Am Weg stehen erloschene Laternen. Kommt der Geist an einer vorbei, kann Ellie E drücken: Der Geist springt hinein, die Laterne entflammt (ein Schwall Licht, alle Wesen im Umkreis von 100 px werden zurückgestoßen), sein Licht ist wieder voll, und er springt wieder heraus. **Diese Laterne brennt danach für immer** und ist ein fester kleiner Lichtkreis in der Welt (gespeichert). Nachdem das Rätsel gelöst ist, ist **der ganze Pilgerweg nachts beleuchtet**: ein sicherer Weg durch die Nacht als bleibende Belohnung.
6. **Scheitern:** Fällt sein Licht auf null, erlischt er fast, schreit leise auf und flüchtet zurück in seinen Schrein (alle seit dem Start entzündeten Laternen bleiben an, man kann ab dort weitermachen, wenn man es in der nächsten Nacht noch einmal versucht). Stirbt Ellie, wartet er im Kreis zitternd, bis sie zurückkommt oder der Morgen kommt.
7. **Ankunft:** Am letzten Schrein läutet die Glocke von selbst, der Geist springt hinein, und **alle Laternen des Weges leuchten in einer Welle von hinten nach vorne auf**. Die Morgenröte kommt einen Moment zu früh: Das ganze Bild wird kurz golden, die Schattenwesen in der Nähe verbrennen wie bei Sonnenaufgang, dann fällt das Glutreliquiar aus einer großen Lichtsäule. Der Geist bleibt im Schrein und schaut ab da jede Nacht heraus (ein kleiner Bewohner; mit E grüßt er).

**Zahlen (erste Annahme)**
- Licht 100, jede Randberührung −8/s pro Wesen, ein Lauscherschuss −15, ein Brecher-Rammstoß −30, Laterne +100 (voll). Ellie in seinem Kreis regeneriert 1 Licht/s.
- Dauer etwa 3–4 Minuten, also etwa eine halbe Nacht (4 Minuten Nacht), knapp genug, dass man nicht trödeln darf.

**Koop:** Ein Spieler bleibt im Kreis (der Geist läuft), der andere kämpft am Rand. Zu zweit fühlt es sich an wie eine echte Eskorte, allein ist es eine Kunst, zwischen Rand und Mitte zu wechseln. Spielerzahl skaliert die Wellen (wie das Nachtbudget, `players^0.8`).

**Design**
- Laternengeist: 8×9 px, ein Tropfen aus warmem Weißgold mit zwei dunklen Augen, ein Schweif aus Funken. Er hat Gefühle: hüpft, wenn eine Laterne brennt, versteckt sich hinter Ellie (in ihrem Schatten, sortiert hinter ihr), wenn Wesen nah sind, schläft im Schrein ein.
- Sein Lichtkreis: ein gezeichneter Ring aus Pixeln am Boden (warm), der bei wenig Licht unruhig und bläulich wird und Lücken bekommt.
- Laternenstöcke: hoher Stein mit Eisenlaterne, Moos, verrußtes Glas. Erloschen: dunkel und kalt. Brennend: Wärme, Flackern, kleine Motten. Teilen das Aussehen mit dem Stadtlaternenpfahl (`tools/art_lamp.py`), aber älter und aus Stein.
- Klang: Der Geist summt eine kleine Melodie, die schneller wird, wenn er Angst hat. Jede entzündete Laterne spielt einen Ton dieser Melodie. Am Ziel spielen alle zusammen.

---

## 6a. NEU: Das Wurzelgeflecht (gewöhnlich / selten / legendär)

> **Gebaut (2026-11-13):** `RootWeave` (src/entities/puzzles/root_weave.gd, ein `WorldTrial`) + `WeaveCube` (ein Würfel, Interactable) + `WeaveRules` (src/systems/weave_rules.gd, pur; Spiegel von `tools/check_root_weave.py`, das jedes Geflecht in data/puzzles.json löst und Mindestgriffe prüft: gewöhnlich 3, selten 6, legendär 12). Host-autoritativ: der Host prüft einen Griff, alle Peers spielen ihn deterministisch nach (`_rpc_do`), Späteinsteiger bekommen den Stand (`_rpc_state`). Art `py -3 tools/art_root_weave.py [preview.png]` (Würfel: 3 Formen, Keim zu/offen, 2 Dornen, je schlafend/wach/gold; Herz schief/dunkel/gold aufgerichtet; Krone zu/blühend; Runen zeichnet das Spiel aus data/puzzle_runes.json), Klänge `py -3 tools/audio_root_weave.py`. Wurzeln, Saft, Pulse und Erdbrocken sind Pixel im Code. Die drei Geflechte stehen bisher nur in der **Rätselwelt** (`--trials` bzw. ENTWICKLER -> RÄTSELWELT BETRETEN, `TrialLevel`: flach, leer, nie gespeichert, mit Irrlicht, Hortkrähe, Rabe und Startausrüstung): Keimling (Saftweg, 3 Griffe), Geflecht (7 Griffe, eine Lösung), Altes Geflecht (17 Würfel, vier Keime, Dornen, Einwegwurzeln, **12 Griffe, genau eine kürzeste Lösung**, die zweimal einen Keim kurz weckt). Entscheidungen der Nutzerin: kein Maß-Bonus, keine Hilfe, nachts friedlich. Abweichung: ZURÜCKZIEHEN ist ein Tipp auf E am Herzen (kein Halten). Test `tools/test_root_weave.tscn` (`ROOT WEAVE OK`), Look `tools/preview_root_weave.tscn -- --dir=/abs [--night]`. Noch nicht: Geflechte in der echten Welt, Karte, Netzwerktest mit zwei Prozessen.

> Konzept 2026-11-13. Idee der Nutzerin: ein halb eingegrabener magischer Würfel, den Ellie an- und ausschaltet; wenn er erlischt, wachsen Wurzeln, neue Würfel steigen aus dem Boden, und welche man an- und ausschaltet, verändert das ganze Bild.

**Fantasie:** Mitten auf einer Lichtung steckt ein Würfel aus dem Stein der Wächterin schief im Boden, halb von Erde und Wurzeln verschluckt. Er summt und leuchtet teal. Wer ihn löscht, weckt das, was unter ihm schläft: Wurzeln brechen aus der Erde, und rundherum steigen weitere Würfel auf, verbunden durch ein Geflecht, durch das Licht fließt. Jeder Griff an einen Würfel schickt einen Puls durch seine Wurzeln, und das ganze Bild kippt.

### Die Teile
| Teil | Aussehen | Regel |
|---|---|---|
| **Herzwürfel** (Prüfstein) | größer (24 px), schief, halb eingegraben, ein Auge auf der Oberseite | Start: leuchtet. E „LÖSCHEN“ = Rätsel beginnt. Danach nicht mehr drückbar; **E „ZURÜCKZIEHEN“** = alles zurück. Trägt die Fortschrittsperlen. |
| **Wurzelwürfel** | 14 px, Rune auf der Stirnseite, wach = Teal-Rune + Lichtadern, schlafend = grau, matt | E „BERÜHREN“: schaltet **sich selbst und jeden Würfel, zu dem eine Wurzel von ihm führt** um. |
| **Keimwürfel** | wie ein Wurzelwürfel, aber mit einem Trieb oben (geschlossene Knospe) | Wird er zum **ersten Mal** wach, wachsen aus ihm neue Wurzeln und Würfel (in ihrem festen Startzustand). **Gewachsenes bleibt**, auch wenn der Keim wieder erlischt (bis zum Zurückziehen). |
| **Dornwürfel** | von Dornenranken umklammert, keine Rune sichtbar | Kann nicht berührt werden (E zeigt nichts, Ellie zuckt zurück). Nur Pulse der Nachbarn schalten ihn. |
| **Einwegwurzel** | Wurzel mit Dornen, die in eine Richtung zeigen, der Saft fließt sichtbar nur in diese Richtung | Puls läuft nur in Pfeilrichtung, nicht zurück. |
| **Kronwürfel** (Ziel, nur „Saftweg“) | größer, mit einer Krone aus geschlossenen Kristallblättern | Wird nicht gedrückt, er ist das Ziel. |

### Die zwei Ziele
- **Saftweg** (gewöhnlich): Der Kronwürfel blüht, sobald eine **ununterbrochene Kette wacher Würfel** vom Herzwürfel bis zu ihm reicht (Licht fließt sichtbar entlang der wachen Kette und staut sich am ersten schlafenden Würfel: man sieht, wo es hakt).
- **Ganzes Geflecht** (selten / legendär): **Alle Würfel gleichzeitig wach**, auch alle gewachsenen. Wer zu früh alle wach hat, aber einen Keim noch nicht gezündet hat, ist nicht fertig: Die Knospe am Keim leuchtet als Hinweis.

### Ablauf
1. **Entdecken:** Glühwürmchen sammeln sich nachts um den Herzwürfel, am Tag summt er leise, wenn man näher als 80 px kommt. Das Auge öffnet sich (Prüfstein-Regel 7.1).
2. **Löschen:** E am Herzwürfel. Ellie legt beide Hände auf (`Player.begin_touch`), das Teal zieht sich in den Boden zurück, ein dumpfer Herzschlag, dann reißen Wurzeln strahlenförmig aus der Erde (wachsen Pixel für Pixel, Erdbrocken fliegen), und die erste Stufe Würfel steigt auf (Schnitt-Shader wie die aus der Erde brechende Truhe, `LootChest.rise`). Manche wach, manche schlafend.
3. **Spielen:** E an einem Wurzelwürfel. Kurzer Handgriff (schnelle Variante von `begin_touch`, 0,35 s). Der Würfel kippt sofort um, dann **läuft der Puls sichtbar die Wurzeln entlang** (0,25 s pro Wurzel, ein Lichtfunke) und schaltet am Ende den Nachbarn. Ursache und Wirkung sind immer zu sehen.
4. **Vorschau (Fairness):** Steht Ellie an einem Würfel (Prompt sichtbar), schimmern die Wurzeln, die er treffen würde, schwach, und die betroffenen Würfel zittern einen Pixel. Man kann also planen, ohne zu probieren.
5. **Wachsen:** Ein Keim, der zum ersten Mal wach wird, öffnet seine Knospe, neue Wurzeln schießen aus ihm, neue Würfel steigen auf, manchmal auf einem Hang oder hinter einem Busch (Laufwege gehören dazu).
6. **Gelöst:** Ein goldener Ring läuft durch das ganze Geflecht, alle Runen werden gold, der Herzwürfel richtet sich mit einem Ruck gerade auf und stößt das Moos ab, die Wurzeln ziehen sich als goldene Adern in den Boden zurück und bleiben als Muster liegen. Die Truhe kommt **aus der Erde** am Kronwürfel bzw. am Herzwürfel (Wurzeln heben sie heraus, gleiche Technik wie der Krähenschatz).
7. **Zurückziehen:** E am Herzwürfel. Die Würfel sinken, Wurzeln kriechen zurück, der Herzwürfel leuchtet wieder. Kein Schaden, nichts verloren. Weggehen (> 400 px für 60 s) zieht ebenfalls zurück.

### Warum es schwer wird (und trotzdem fair)
Der Kern ist ein Umschalträtsel über einem Graphen (jeder Druck schaltet sich und seine Wurzelnachbarn). Das allein ist schon knifflig, weil jeder Druck mehrere Würfel ändert. Die eigenen Zutaten machen es zu **unserem** Rätsel:
- **Wachstum ändert das Brett.** Je nachdem, wann man einen Keim zündet, kommen neue Würfel mit festen Zuständen dazu. Die Reihenfolge zählt.
- **Der Kniff „kurz wecken“:** Weil Gewachsenes bleibt, kann man einen Keim wecken und gleich wieder löschen. Das ist die Aha-Lösung vieler legendärer Geflechte (siehe Beispiel).
- **Dornwürfel** zwingen zu Umwegen über Nachbarn, **Einwegwurzeln** brechen die Symmetrie (A schaltet B, aber B nicht A).
- **Doppelt drücken ist nutzlos**, außer es lässt etwas wachsen. Das merkt man beim Spielen.

**Lösbarkeit:** Jedes Geflecht wird beim Backen von einem Löser geprüft (Breitensuche über Zustand + gewachsene Keime; klein genug, 16 Würfel = 65 536 Zustände pro Wachstumsstand). Gespeichert werden die kürzeste Lösung („Maß“) und wie viele Lösungen es gibt. Ein Geflecht ohne Lösung, mit Maß < 3 oder einer Lösung, die ohne Nachdenken durch bloßes Abklappern fällt, wird verworfen.

### Stufen
| Stufe | Würfel | Ziel | Zutaten | Maß |
|---|---|---|---|---|
| gewöhnlich „Keimling“ | 4–6 | Saftweg | nur Wurzelwürfel | 2–4 |
| selten „Geflecht“ | 6–9 | Ganzes Geflecht | + 1 Keim, + Dornwürfel | 4–6 |
| legendär „Altes Geflecht“ | 14–18 | Ganzes Geflecht | + 3–4 Keime (Wachstum in mehreren Stufen, auch Keime aus Keimen), Einwegwurzeln, Dornen | mindestens 12, möglichst eine einzige kürzeste Lösung |

### Kleines Beispiel zum Kniff „kurz wecken“ (vom Löser geprüft; die echten legendären Geflechte sind größer, siehe oben)
```
        H ── K                 Start nach dem Löschen:  A wach, B schlafend (Keim),
        │     ╲ (K→F)                                    C schlafend, D wach
   (D→H)│      ╲               Wächst aus B:  E schlafend, F Dorn schlafend, G Keim wach
        │   G ──→ C (G→C)      Wächst aus G:  H schlafend, K wach
   D ── A ── B ── E
   │         │    │
   └─── C ───┘    F(Dorn) ── G
```
Wurzeln: A–B, B–C, C–D, D–A (der Ring um das Herz), B–E, E–F, F–G, G→C, G–H, H–K, K→F, D→H.
**Kürzeste Lösung (5):** C, C, G, K, E. Der Trick: Das erste C weckt B, B wächst, und weil G schon wach aufsteigt, wachsen H und K gleich mit. Das zweite C löscht B wieder, aber das Gewachsene bleibt. Danach schalten G, K (über die Einwegwurzel auf F) und E den Rest wach. Wer B einfach direkt drückt, verheddert sich.

### Koop
Jeder kann jeden Würfel berühren, der Host ordnet die Griffe (ein Griff sperrt das Geflecht für die Dauer seines Pulses, ~0,5 s, ein zweiter Griff wird so lange gepuffert). Koop hilft durch Laufwege und Mitdenken, nie durch Pflicht. Die Truhe gehört allen (Ziehung +1 pro Spieler in der Nähe wie bei allen Truhen).

### Design
- **Würfel:** der hellviolette Stein der Wegstatuen, leicht verwittert, abgerundete Kanten, Moos auf der Oberseite, 3/4-Ansicht wie alle Props. Die Stirnseite trägt eine der sechs **Prüfrunen** (7.3); wach = Rune und feine Adern teal (unlit), schlafend = Rune als dunkle Ritzung. Halb eingegraben: ein Erdwulst mit Wurzelansätzen um den Fuß.
- **Wurzeln:** pflaumen-violette Holzwurzeln wie unter den Bäumen, 2–3 px dick, gekrümmt (Catmull-Rom wie die Trampelwege), mit Erdaufwurf an den Seiten. In jeder Wurzel eine 1 px Saftader, die teal fließt, wenn beide Enden wach sind, und dunkel ist sonst. Einwegwurzeln haben kleine Dornen in Flussrichtung.
- **Dornwürfel:** schwarze, glänzende Dornranken (Leerenschwarz mit violettem Rand) umklammern ihn; erst wenn er wach wird, glimmt die Rune durch die Lücken.
- **Keim:** eine geschlossene Knospe oben auf dem Würfel, die sich beim Wachsen zu einer Blüte aus Kristallblättern öffnet (BloomOrb-Sprache, aber als Sprite).
- **Klang:** jeder Würfel ein Glaston (Tonhöhe nach Rune), der Puls ein leises Holzknacken, das die Wurzel entlangläuft, Wachsen ein tiefes Reißen und Grollen, Gelöst = der Akkord der Wächterin (7.4), Zurückziehen = die drei Töne absteigend.
- **Ort:** Lichtungen und flache Hänge; die Würfel verteilen sich auf 6–14 Tiles Radius, gelegentlich auf einer Stufe oder hinter einem Felsen, damit man den Überblick suchen muss. Nie im Stadtlicht.

### Technik (Vorschlag)
- `RootWeave` (src/entities/puzzles/root_weave.gd) extends `WorldTrial`, Art `root_weave` in `Puzzles.KINDS`. Daten in `data/puzzles.json` `placed`: `{id, kind "root_weave", tile, tier, goal "path"|"all", cubes {id: {at [dx, dy] Tiles vom Herz, kind, lit, from (Keim, der ihn wachsen lässt)}}, roots [[a, b, one_way]], crown}`.
- `WeaveRules` (pur, src/systems): `press(state, id)`, `grow(state)`, `solved(state, data)`, `solve(data)` (Breitensuche, gibt Maß + Lösung). Genutzt vom Host, vom Bake-Check und vom Test.
- Host-autoritativ: `request_press(id)` → `_rpc_press(id, seq)` (jeder Peer spielt Puls und Wachstum selbst ab, Zustand ist deterministisch), `request_withdraw`, Snapshot (`lit`-Bits + gewachsene Keime) für Späteinsteiger. Gespeichert wird nur „gelöst“ (Versuche nicht).
- Würfel = kleine `Interactable`s (Prompt nur, wenn drückbar), Wurzeln = ein selbst gezeichneter Knoten pro Geflecht (Pixel, nur neu gezeichnet bei Änderung), Pulse/Adern unlit.
- Art `py -3 tools/art_root_weave.py` (Ellipsoid-/Box-Renderer wie die Truhen: Herz, Würfel ×6 Runen × wach/schlafend, Dorn, Keim mit Knospe/Blüte, Kron; Glow-Blätter), Klänge `py -3 tools/audio_root_weave.py`. Löser-Check `tools/check_weaves.py` (oder im Godot-Test). Test `tools/test_root_weave.tscn` (Löser, Drücken, Wachstum, Einweg, Dorn, Zurückziehen, Maß-Bonus, Speichern, `ROOT WEAVE OK`), Look `tools/preview_root_weave.tscn`.

### Entschieden
- Kein Maß-Bonus, keine Hilfe nach Fehlversuchen, nachts bleibt das Rätsel friedlich (2026-11-13).

---

## 6b. NEU: Sternenspiegel (gewöhnlich / selten / legendär)

> **Gebaut (2026-11-13):** `StarMirror` (src/entities/puzzles/star_mirror.gd, ein `WorldTrial`, Art `star_mirror`) + `StarStone` (ein Mondstein, Interactable). Ellie trägt Steine frei in alle acht Richtungen: `Player.start_carry/end_carry/carry_stone` (Sheet `player_carry_stone.png` aus `py -3 tools/art_hero_carry_stone.py`: dieselben Posen wie das Brett der Holzfällerhütte, der Stein über den neuen Posen-Schlüssel `rock` von art_hero3d.py eingebacken; 62 % Tempo, kein Sprint, keine Schläge, kein Schattenschritt, kein Essen). Teichrand, Mondsteine und Feldsteine: `py -3 tools/art_star_mirror.py [preview.png]`; Wasser, Spiegelbild, Lichtlinien und Lichtsäule zeichnet das Spiel. Klänge `py -3 tools/audio_star_mirror.py`. Host-autoritativ (`_rpc_pick`, `_rpc_drop`, `_rpc_state` für Späteinsteiger); wer fällt, lässt den Stein fallen. Drei Teiche in der **Rätselwelt** (`trial_world`): Sichel (5 Sterne, links/rechts), Rabe (7 Sterne, 8 Steine, dreht sich 70° über die Nacht, schwache Sterne bei Neumond weg), Wächterin (9 Sterne, 11 Steine, diagonal gespiegelt, dreht sich 90°, Linien nur bei Vollmond). Dev: ENTWICKLER -> STERNENSPIEGEL: ZUM TEICH / ZURÜCKSETZEN, MOND: VOLL / NEU. Test `tools/test_star_mirror.tscn` (`STAR MIRROR OK`), Look `tools/preview_star_mirror.tscn -- --dir=/abs [--id=stars_rabe]`. Noch nicht: Teiche in der echten Welt, Netzwerktest mit zwei Prozessen.

**Fantasie:** An einem stillen Teich liegen Mondsteine im Gras. Nachts spiegelt das Wasser ein Sternbild, das es am echten Himmel nicht gibt. Ellie muss die Steine so auf die Wiese legen, dass sie das Spiegelbild nachbilden.

**Ablauf**
1. **Lesen:** Nachts zeigt das Wasser 5–9 helle Punkte und schwache Linien, gespiegelt und langsam drehend; die vier Runen der Feldsteine (Mond, Auge, Flamme, Feder an den Ecken des quadratischen Feldes neben dem Teich) spiegeln sich mit, so findet man das Feld im Bild wieder.
2. **Tragen:** E hebt einen Stein auf (Trage-Sheet), langsam, kein Sprint; ein Punkte-Ring zeigt, wo er landet (hell, wenn er auf einem freien Stern landen würde). E legt ihn ab.
3. **Rückmeldung:** Ein Stein in der Nähe (13 px) eines freien Sterns rastet ein, leuchtet, Licht läuft zu jedem schon belegten Nachbarn der Figur, sein Stern im Teich glüht warm. Falsch gelegte Steine bleiben dunkel, nichts wird zurückgesetzt. Nicht ins Wasser.
4. **Gelöst:** Alle Sterne belegt: Lichtsäule aus dem Teich, die Truhe steigt am Westufer aus der Erde.

**Mond:** Bei Neumond zeigen Figuren mit `faint` nur die helleren Sterne, Figuren mit `lines: full_moon` ihre Linien nur nahe Vollmond. Am Tag ist der Teich nur Wasser: das Bild einprägen und tagsüber legen geht.

| Stufe | Sterne | Steine | Spiegelung |
|---|---|---|---|
| gewöhnlich | 5 | 5 | links/rechts |
| selten | 7 | 8 | links/rechts, dreht sich |
| legendär | 9 | 11 | diagonal, dreht sich, Linien nur bei Vollmond |

---

## 6c. Verteilung in der Welt (2026-11-13)

`python3 tools/place_trials.py [--write] --variants=<pfad>` verteilt die Prüfungen fair auf die benannten Gebiete und schreibt sie mit `"auto": true` und `"area"` in data/puzzles.json `placed` (von Hand gesetzte bleiben). Ein Ort muss trockenes Land weit innerhalb der Küste sein, auf einer Höhenebene, auf Bodenkacheln für den ganzen Fußabdruck, fern von Flüssen, Seen, Stadt (90 Kacheln um die Hütte), Start, Story-Orten und Wegstatuen, mindestens 46 Kacheln von jeder anderen Prüfung; Wege (Irrlichtroute, Krähenhügel, Rabenstationen) werden auf derselben Ebene gesucht. Unter den guten Orten gewinnt der, der am weitesten von allen schon gesetzten liegt.

| Gebiet | Prüfungen |
|---|---|
| Nebelwald | Irrlicht, Hortkrähe, Rabe (von Hand, bei der Stadt), Geflecht gewöhnlich, Sternenspiegel gewöhnlich (Feder) |
| Die Lichtung | Irrlicht, Hortkrähe, Geflecht selten, Sternenspiegel gewöhnlich (Sichel) |
| Glasklippen | Irrlicht, Hortkrähe, Rabe, Geflecht legendär (12 Griffe), Sternenspiegel selten (Rabe) |
| Versunkene Ruinen | Irrlicht, Hortkrähe, Rabe, Geflecht gewöhnlich, Sternenspiegel legendär (Wächterin) |
| Das Leerenblühen | Irrlicht, Hortkrähe, Geflecht legendär (11 Griffe, gespiegelte Variante), Sternenspiegel selten (Eule) |
| Hexenwald | nur Hortkrähe, Rabe und ein Geflecht selten (gespiegelte Variante) |

Geflechte, die zweimal vorkommen, sind gespiegelt und haben einen neuen Startzustand (neue Lösung); die zweite legendäre Variante hat 11 Griffe (Wahl der Nutzerin), `tools/check_root_weave.py` verlangt für legendär mindestens 11. Zwei neue Sternbilder: Feder (5 Sterne, oben/unten gespiegelt) und Eule (7 Sterne, 8 Steine, oben/unten, dreht sich 60°). Jeder Haltepunkt einer Irrlichtroute bleibt frei von Pflanzen (`Puzzles.clear_spots`). Test `tools/test_trials_world.tscn` (`TRIALS WORLD OK`; mit `-- --dir=/abs` ein Bild je Prüfung).

---

## 7. Designkonzept: die Sprache der Prüfungen

### 7.1 Der Prüfstein (gemeinsames Element)
Jedes Rätsel hat genau einen Prüfstein, ein kleines Objekt aus dem gleichen Material wie die Wegstatuen (heller violetter Stein, dunkle Kristalle, Risse, Moos). Er ist **der Wiedererkennungswert**: Wer einmal einen gesehen hat, weiß, dass hier eine Prüfung ist.
- **Schlafend:** grau, Moos, ein mattes Teal-Auge in der Mitte, das bei Annäherung (60 px) langsam aufgeht. Damit kündigt sich das Rätsel an, ohne Text.
- **Aktiv:** Teal-Einlagen glühen, 3–7 kleine **Fortschrittsperlen** um das Auge füllen sich (wie die Refine-Perlen).
- **Gelöst:** Gold. Ein Lichtstrahl steigt einmal auf, danach glimmt er golden und das Moos fällt ab. Auf der Karte wird aus dem „?“ ein kleines Truhensymbol.
- Bei der Irrlichtspur ist der Prüfstein der Blütenfleck, beim Krähenschatz der Ring am Krähenbein; nicht jedes Rätsel braucht einen sichtbaren Stein, aber jedes hat diesen Zustandsträger.

### 7.2 Farben und Licht (ergänzt design_guide)
| Bedeutung | Farbe | Wo |
|---|---|---|
| Fortschritt, bereit, „hier lang“ | Teal `#78f4e6` | Perlen, Fäden, Irrlicht, geschlossene Risse |
| Gelöst, Belohnung | Gold `#ffb347` / `#fff2cc` | Prüfstein gelöst, Lichtsäule, Truhe |
| Zurückgesetzt, falsch | Violett-Puls `#9468ee` | ein einziger Puls, dann Ruhe |
| Gefahr, Kreaturen | Magenta (bleibt den Wesen) | Spinnenaugen im Hain, nie für Rätsel-UI |

Alles, was das Rätsel erklärt, ist **unlit** (lesbar bei Nacht), Stein und Holz sind welt-beleuchtet.

### 7.3 Prüfrunen
Sechs eigene Glyphen, 7×7 px, aus Motiven der Welt: **Mond** (Sichel), **Wurzel** (Gabel nach unten), **Auge** (Raute mit Punkt), **Flamme** (Tropfen nach oben), **Welle** (zwei Bögen), **Feder** (Schaft mit Fahnen). Gezeichnet wie die Leerenschrift (`VoidTitle`), aber hell, geritzt statt flüssig. Sie tauchen in der Runenreihe, auf Prüfsteinen und als Hinweise auf, später auch als Kartensymbole.

### 7.4 Klang
- **Motiv der Wächterin:** drei aufsteigende Glastöne (wie die Wegsteine). Ein Ton pro Fortschritt, die Tonhöhe steigt mit den Perlen.
- **Rücksetzen:** die drei Töne absteigend, gedämpft, ein Hauch Rauschen.
- **Gelöst:** ein voller Akkord, danach das Herabsinken der Lichtsäule (`descend`) und der Aufprall der Truhe (`boom`).
- Rätselorte haben eine eigene, leisere Umgebung (der Hain fast still, die Narbe brummt, der Pilgerweg hat Wind und eine ferne Glocke).

### 7.5 Entdeckung und Karte
- **Locken statt zeigen:** Glühwürmchen sammeln sich nachts um schlafende Prüfsteine (`flora_glow`-Gruppe), Krähen kreisen über Hortbäumen, die Narbe zeichnet sich auf der Karte als dunkler Fleck ab.
- **Karte:** Ein gesehener Prüfstein bekommt ein „?“ (Gold, klein). Gelöst: ein Truhensymbol. Die Karte zählt pro Gebiet „PRÜFUNGEN 3/9“ unter dem Erkundungsanteil der Biome.
- **Ellie kommentiert** das erste Rätsel jeder Art mit einem Satz (Platzhalter für den Dialogschreiber), danach nie wieder.

### 7.6 Belohnung nach Schwierigkeit
| Rätsel | Truhe | Ankunft |
|---|---|---|
| Irrlichtspur | Wurzelkiste | Lichtsäule über dem Blütenring |
| Krähenschatz (Krähe) | Wurzelkiste | aus der Erde gegraben |
| Krähenschatz (Rabe) | Mondsiegeltruhe (+ Pfand zurück) | aus der Erde gegraben |
| Runenreihe | Mondsiegeltruhe (3 Stelen: Wurzelkiste) | Lichtsäule über der Sonnenuhr |
| Schweigender Hain | Mondsiegeltruhe | steht schon da (das Ziel ist das Erreichen) |
| Rissläufer | Mondsiegeltruhe / Glutreliquiar | fällt aus der Leere, dann Licht |
| Die letzte Laterne | Glutreliquiar + beleuchteter Weg | große Lichtsäule am Zielschrein |
| Wurzelgeflecht | Wurzelkiste / Mondsiegeltruhe / Glutreliquiar (nach Stufe) | Wurzeln heben sie aus der Erde |
| Sternenspiegel | Wurzelkiste / Mondsiegeltruhe / Glutreliquiar (nach Stufe) | Lichtsäule aus dem Teich, Truhe am Ufer |

Prüfungstruhen bekommen einen eigenen Pool-Zuschlag: +1 Ziehung aus dem nächsthöheren Pool, damit sich das Lösen mehr lohnt als eine zufällig gefundene Truhe.

---

## 8. Technik (Vorschlag)

- **Daten:** `data/puzzles.json` `{id, kind, tile, tier, region, params}`; `params` je Art (Wegpunkte der Irrlichtspur, Stelenplätze und Reihenfolge der Runenreihe, Spinnenplätze und Zweige des Hains, Haufen und Stationen des Krähenschatzes, Risse des Rissläufers, Weg, Laternen und Wellen der Laterne). Handplatziert wie Wegsteine und Truhen (`placed`).
- **Knoten:** `Puzzles` (Knoten von `WorldLevel`, Gruppe `puzzles`, host-autoritativ, Muster wie `Waystones`: `request_*`, `_rpc_*`, Snapshot, Speicherschlüssel `puzzles` mit gelösten Ids und dauerhaften Weltänderungen: brennende Laternen, geheilte Narben). Eine `WorldPuzzle`-Basisklasse (`step`, `progress`, `reset`, `solved`, Prüfstein-Zustand), je Art eine Unterklasse (`WispTrail`, `RuneCircle`, `SilentGrove`, `CrowHoard`, `RiftWalk`, `LastLantern`).
- **Belohnung:** `LootChests.reveal(id, tier, pos, style)` mit `style` = `light` (wie die Boss-Truhe), `ground` (aus der Erde), `void` (aus dem Riss), `standing` (Hain). Prüfungstruhen sind keine Testtruhen: sie bleiben gespeichert, geöffnet stehen sie offen, sie verblassen nicht.
- **Nötige Erweiterungen bestehender Systeme**
  - `ShadowSpider`: Zustand `SLEEP` + Weck-Zeiger (Hain).
  - Lärmquellen: eine kleine gemeinsame Funktion „Lärm bei Position mit Stärke“ (gibt es teilweise in `StealthComponent`/`AttackComponent.noise_scale`).
  - `TownManager.light_depth` bzw. `NightBehavior`: zusätzliche **bewegliche Lichtkreise** (Gruppe `mobile_lights`) für den Laternengeist und die entzündeten Laternenstöcke.
  - `ShadowStepComponent`: die Schrittlinie als Signal (`stepped(from, to)`), damit der Rissläufer prüfen kann, ob ein Riss gekreuzt wurde.
  - `PetBehavior`/`WildCorvid.fly_to`: eine gelenkte Flugroute für Hortkrähe und Rabe (die Flugsteuerung gibt es schon).
  - `MapWindow`: Symbole „?“ und Truhe, Zähler pro Gebiet.
- **Tests:** je Art ein Kopflos-Test (Lösen, Scheitern, Zurücksetzen, Speichern, Koop über zwei Prozesse wie bei den Wegsteinen).

## 9. Bauplan (Vorschlag)

1. **Gerüst + Prüfstein + Karte** (`Puzzles`, `WorldPuzzle`, `LootChests.reveal`, Art Prüfstein/Runen, Töne). Erstes Rätsel: **Runenreihe** (rein lokal, keine KI, testet das Gerüst).
2. **Irrlichtspur** (eine bewegte Node mit einfacher Logik).
3. **Krähenschatz** (gewöhnlich, dann selten; nutzt Pet- und Hackensysteme).
4. **Schweigender Hain** (Spinnen-Schlaf, Lärm).
5. **Rissläufer** (Schritt-Signal, Riss-Shader als Dauerobjekt).
5a. **Wurzelgeflecht** (rein lokal, pure Regeln + Löser, kein KI-Anteil; gut als nächstes).
6. **Die letzte Laterne** (bewegliche Lichtkreise, eigene Wellen; das größte Stück).
7. Verteilen: 8–12 Prüfungen pro benanntem Gebiet, nie im Licht der Stadt, bevorzugt an schönen Orten (Plateaus, Wasser, Waldränder, der Hexenwald für die Nebel-Varianten).

## 10. Offene Fragen

- Sollen Prüfungen nach dem Lösen **wiederholbar** sein (z. B. die Irrlichtspur alle 7 Tage mit kleiner Truhe), oder einmalig wie in Genshin?
- Sollen Prüfungen erst nach einem Story-Punkt erscheinen (z. B. nach dem ersten erweckten Wegstein, „die Wächterin erkennt dich an“)? Das würde die Lore schön verankern.
- Wie viel Text darf Ellie zu Rätseln sagen? (Vorschlag: ein Satz beim ersten Mal jeder Art.)
- Darf die Letzte Laterne die normale Nacht in der Nähe ersetzen (der Weg zieht alle Wesen an) oder läuft sie zusätzlich?
