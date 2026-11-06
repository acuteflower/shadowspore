# Konzept: Wind, Pflanzenreaktionen und lebendiger Bodenbewuchs

Status: Implementiert. Das ursprüngliche Gestaltungskonzept folgt unten; technische Umsetzung und geprüfte Grenzen stehen im nächsten Abschnitt.

## Umsetzung

- `WorldWind` (`src/world/world_wind.gd`) wird pro Welt geladen. Eine gemeinsame pausierbare Spielzeit steuert Richtung, ziehende Böen, Vegetationsmaterialien und Luftpartikel. Werte für Dichte, Biomeinfluss und Partikelgrenzen stehen in `data/wind.json`.
- `Bush` und `Tree` verwenden dieses Windfeld; bestehende Treffer-, Ernte-, Durchlauf- und Fällreaktionen behalten Vorrang. Die biomeabhängige Windstärke wird beim Laden der Pflanze bestimmt.
- `MeadowDetails` enthält jetzt 24 Varianten. Pro Chunk bleibt es bei einer gemeinsam gezeichneten Pflanzenmenge. Jeder Chunk hat ein 64×64-Kontaktfeld; nur berührte Zellen speichern Impuls und Abklingzeit. Überstrichene Bewegungsstrecken werden alle 0,08 Sekunden für Spieler, Spinnen, Hasen und Waldsäuger aufgenommen. Teleports werden übersprungen. Nach 0,9 Sekunden ist eine unberührte Zelle wieder neutral. Der Shader hält Wurzeln fest und verformt die oberen Teile in ganzen Pixeln.
- Pflanzenpositionen bleiben deterministisch. Zusätzlicher Bewuchs verändert keine größeren Props und keine Kampf-/Loot-Zufallsfolge. Freizuhaltende Bereiche und Bodenmasken werden weiter beachtet.
- Sparsame natürliche Luftpartikel stammen aus geladenen nahen Pflanzen: Blüten geben Blütenblätter ab, Gräser Samen, Farne/Blattpflanzen kleine Blätter. Kurze blasse Böenspuren sind bei nahen Raubgegnern ausgeschlossen. Dialoge, Karten und gesperrte Storymomente blenden Luftdetails aus und verhindern neue Umgebungs-Emissionen. Die Partikel verbleiben in Weltkoordinaten, altern weiter und besitzen eine harte Grenze von acht. Innenräume erhalten keine Außenluftpartikel.
- Nahes Pflanzenrascheln nutzt die vorhandene leise `assets/audio/hut/rustle.wav` mit variierter Tonhöhe und Auslösepause. Schleichen ist leiser; es gibt keine zusätzliche Meldung an die Gegnerwahrnehmung. Die Reaktion erzeugt keinen Bewegungsmalus und keine Sammelressourcen.

Prüfung: `tools/test_wind.tscn` prüft alle 24 Varianten, Kontakt einschließlich gerenderter Pixelverformung und feststehender Wurzeln, vollständige Erholung, Teleport-Unterdrückung, Pause, Zeitlupe, UI-Unterdrückung und Partikelgrenze. Tages-/Nachtbilder landen unter `/tmp/wind-meadow-day.png` und `/tmp/wind-meadow-night.png`. Zusätzlich wurde `tools/test_story_start.tscn` mit Gully, Verletzung und Wächterspinnen geprüft.

Die Gestaltungswerte unten sind Richtwerte; der erste Stand bleibt bewusst sparsam. Ein vollständiges Wetter-/Sturmsystem und persistente niedergetretene Pfade bleiben außerhalb des Umfangs.

## Gewünschtes Spielgefühl

Eine sanfte Böe erreicht den Wegrand. Zuerst neigen sich feine Halme, dann bewegen sich Blumen, Büsche und Baumkronen etwas träger in dieselbe Richtung. Zwei oder drei Samen steigen auf und werden mitgetragen. Ellie läuft durch einen kleinen Grasfleck: Die Halme weichen ihrer Bewegung aus, federn kurz nach und richten sich wieder auf. Anschließend wird es wieder ruhig.

Die Bewegung soll auf dem bestehenden Pixelraster bleiben und die ruhige, mystische Stimmung des Waldes tragen. Figuren, Kampfhinweise und Dialoge bleiben lesbar.

## Ausgangslage im Projekt

- `MeadowDetails` zeichnet zwölf kleine dekorative Varianten gemeinsam pro geladenem Chunk. Die bestehenden Gräser, Wildblumen, Farne und Rosetten haben eine einfache Windbewegung im Shader, bisher ohne Kontaktreaktion.
- `Bush` und `Tree` haben eigene zeitabhängige Wippbewegungen. Büsche reagieren bereits beim Betreten, Bäume auf Treffer. Diese Bewegungen sollen mit dem neuen Wind verbunden werden, ohne Treffer-, Ernte- oder Fällanimationen zu überschreiben.
- Der Weltgenerator berücksichtigt Wege, Steinflächen, Klippen, größere Objektgrundflächen und freizuhaltende Storybereiche. Diese Freiräume bleiben für zusätzlichen Bewuchs erhalten.

## 1. Ein gemeinsamer Wind

Ein Welt-Windsystem steuert Richtung, Grundstärke und räumlich wandernde Böen. Langsame Richtungsänderungen; sanfter Grundwind mit Pausen und unregelmäßigen stärkeren Schüben. Eine Böe läuft sichtbar durch die Umgebung, statt alle Pflanzen gleichzeitig auszulenken. Kleine individuelle Unterschiede verhindern Gleichschritt.

Startwerte zur visuellen Abstimmung:

| Element | Reaktion |
|---|---|
| Kurzes Gras | Schnell, meist 1 logischer Pixel Auslenkung |
| Lange Halme/Samenstände | 1–3 Pixel, etwas Nachschwingen |
| Kleine Blumen | Stiel neigt sich, Blütenkopf schwingt etwas verzögert |
| Farne und breite Blätter | Schwerer und gedämpfter, verschiedene Wedel reagieren versetzt |
| Büsche | Geringe Neigung und lokale Blattbewegung; Grundfläche bleibt stehen |
| Bäume | Träge Kronenbewegung; Stamm und Kollisionsgrundfläche bleiben stabil |

Wurzeln bleiben fest. Verformung nimmt nach oben zu. Keine weichgefilterten Texturen oder kontinuierlich rotierenden Pixelbilder. Kräftigere Treffer-/Fällbewegungen haben Vorrang; Wind wird sanft überlagert. Eine gemeinsame Spielzeit respektiert Pause und Zeitlupe, statt Shader-TIME und unabhängige Echtzeit-Uhren zu mischen.

Biome verändern die Stärke: offene Wiesen sind windiger, Waldinneres ist ruhiger, Lichtungen erhalten gelegentliche Böen. Ein Wetter-/Sturmsystem gehört zunächst nicht dazu.

## 2. Kontakt mit Pflanzen

Dekorative Pflanzen reagieren rein optisch auf das Durchlaufen. Kein neuer E-Prompt, Sammeln, Schaden, Abbau oder zusätzlicher Bewegungsmalus.

- Druck richtet sich nach Bewegungsrichtung, Abstand und Tempo. Die tatsächliche überstrichene Strecke wird berücksichtigt, damit auch schnelle Bewegungen die Halme erfassen.
- Schleichen: kleine leise Berührung; normales Gehen: sichtbares Ausweichen; Sprint: stärkere Reaktion mit wenigen losen Samen.
- Kontakt überlagert den Wind. Halme federn ungefähr 0,4–0,9 Sekunden nach und kehren vollständig zurück. Kein dauerhaft plattgetretener Boden im ersten Umfang.
- Vorhandenes Buschrascheln bleibt erhalten und wird nicht doppelt ausgelöst. Neue leise Raschelvarianten werden begrenzt und nur aus unmittelbarer Nähe abgespielt. Kosmetisches Rascheln verändert zunächst keine Gegnerwahrnehmung.
- Ellie und andere Spieler lösen Kontakte aus. Größere Tiere und Schattenwesen können denselben Weg nutzen, mit begrenzter Einflussstärke. Die erste Abnahme konzentriert sich auf Ellie.

Technische Richtung: ein kleines, begrenztes Kontaktfeld für nahe sichtbare Chunks, das Bewegungsimpulse speichert und ausklingen lässt. Das bereits gemeinsam gezeichnete Kleinzeug liest dieses Feld im Shader. Keine eigene Physikfläche oder Prozessfunktion pro Grashalm. Entfernte Chunks erzeugen keine Kontaktarbeit.

## 3. Mehr Pflanzen, gezieltere Verteilung

Die bisher zwölf dekorativen Varianten werden auf ungefähr 24 erweitert. Geplant sind zwölf zusätzliche Formen:

- Drei Grasvarianten: gebogene feine Halme, niedriges dichtes Büschel, lockere Samenstände.
- Drei Blütenvarianten: kleine cremefarbene Sternblüten, hängende lilafarbene Glöckchen, vereinzelte staubigrosa Wildblüten.
- Zwei Farnvarianten: kleiner entrollender Wedel, asymmetrischer Fächer.
- Zwei Blattformen: breite bodennahe Blätter und ein lockeres Sauerampfer-/Kleepolster.
- Zwei trockene Formen: einzelne strohfarbene Halme und dunkle abgeblühte Samenstände.

Vorwiegend 5–18 Pixel hoch, wenige Akzente bis etwa 22 Pixel; Ellie ist ungefähr 42 Pixel hoch. Begrenzte bestehende Grün-, Creme-, Flieder- und Altrosatöne. Blüten sind kleine Akzente; die Mehrheit bleibt grün. Keine zusätzlichen leuchtenden Sammelobjekte.

Der neue Bewuchs wächst in Flecken: lockere Wildblumen in offenen Bereichen, Farne bei Büschen und Waldrändern, vereinzelte trockene Formen auf kargeren Flächen. Zielwert zunächst etwa 25–35 Prozent mehr kleine Pflanzen in geeigneten Wiesenbereichen; weniger auf Glasklippen und in wichtigen Kampfflächen. Pflanzdichte und Mischung werden bei Tageslicht und Nacht abgestimmt. Wege, Gully, Ritterfund, Wegweiser und Schattenriss-Kampfbereich bleiben erkennbar. Neue Verteilung bleibt bei Chunk-Neuladen stabil und verändert keine bestehenden Loot-/Gegner-Zufallsfolgen.

## 4. Wind dezent in der Luft zeigen

Die Luftpartikel folgen demselben Windfeld wie der Bewuchs und sind in Weltkoordinaten verankert. Kamerawechsel erzeugen keinen ständig gleich gefüllten Bildschirmfilter.

- Hauptmittel sind vereinzelte natürliche Partikel: ein kleines Blatt, ein Samenfaden, wenige Blütenblätter an blühenden Pflanzen. Sichtbare Quellen helfen der Wirkung.
- Als Anfangsbudget ungefähr 2–5 gleichzeitig sichtbare Partikel im normalen Bildausschnitt, während kurzer Böen höchstens etwa 6–8. Auch vollständig leere Phasen sind gewollt.
- Kleine, klar gepixelte Formen von meist 1–3 Pixeln, begrenzte Flugstrecken, sanftes Steigen und Fallen. Kein flächiger Pollenregen, Leuchten oder Nebelschleier.
- Gelegentlich bei einer stärkeren Böe eine oder zwei sehr schwache, unterbrochene Luftspuren: etwa 8–18 Pixel lang, ein Pixel dünn, rund 0,2–0,5 Sekunden sichtbar, anfangs ungefähr 6–10 Prozent Deckkraft. Sie liegen lokal und bewegen sich mit der Böe. Die genauen Werte sind Abnahmewerte, keine Pflicht zur ständigen Darstellung.
- Luftspuren dürfen weder wie Angriffsbögen noch wie magische Projektile aussehen. Wenn sie im Kampf oder vor kontrastreichem Boden stören, fallen sie weg; die natürlichen Partikel und Pflanzenbewegungen tragen den Wind weiter.
- Neue Partikel werden während Dialogen und wichtigen Cutscene-Momenten reduziert beziehungsweise nicht erzeugt. In der Nacht unauffällig abdunkeln. Harte Obergrenzen und Wiederverwendung verhindern Ansammlungen nach längeren Spielsessions.

## Umsetzung in zusammenhängenden Schritten

1. Gemeinsames Windfeld samt Spielzeit und Anschlüssen für Kleinzeug, Büsche und Kronen. Zuerst mit vorhandener Vegetation abstimmen.
2. Kontaktfeld, Ausweichen, Rückfedern und sparsam ausgelöstes Rascheln.
3. Zusätzliche Pflanzenformen und natürliche Biommischungen; Dichte an mehreren Stellen abstimmen.
4. Weltgebundene Luftpartikel und optionale sehr schwache Böenspuren. Im Zusammenspiel weiter reduzieren, wo das Bild unruhig wird.

## Abnahme

Ein kurzer Lauf vom Gully über den Ritter zum Wegweiser soll zusammenhängende Windbewegung, sichtbare Kontaktreaktionen und ruhigere Zwischenphasen zeigen. Danach dieselben Stellen bei Nacht, im Dialog und im Kampf prüfen. Ebenso Rückkehr nach Chunk-Neuladen, mehrere nahe Spieler, pausierter Dialog und Zeitlupe: kein Wind-Zeitsprung, kein Pflanzendrift, keine Partikelansammlung und keine deutlich erhöhte Last bei mehr Bewuchs. Bestehende Ernte-, Treffer- und Fällanimationen bleiben funktionsfähig.

Nicht Teil dieses ersten Umfangs: Wetterwechsel, Sturm, persistente Fußpfade, neue Sammelressourcen, neue Stealth-Regeln oder eine eigene Schattenverderbnis-Reaktion der gesamten Natur.
