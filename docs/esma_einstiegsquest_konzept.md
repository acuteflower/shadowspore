# Esmas Einstieg – Der verstummte Krähenbaum

Konzept vom 2026-11-10. Noch kein Implementierungsauftrag. Verbindliche Reihenfolge: 1. Krähenbaum zeichnen und einbauen, 2. Esmas fehlende Animationen und Inszenierung, 3. Quest als Entwicklertest zusammensetzen.

Dieses Konzept ersetzt für Esmas Einstieg den früher angedachten Sammelauftrag aus hexenwald_nebel_konzept.md. Die Ohrringe der Klarheit sind die Belohnung für die Befreiung des Baums. Die reguläre Story-Anbindung und ein späterer Boss bleiben ausdrücklich außerhalb dieses ersten Durchgangs.

## 1. Krähenbaum: Wahrzeichen und zukünftiger Kampfplatz

Ein einzigartiger, sehr großer alter Baum im Hexenwald, kein vergrößerter Standardbaum. Arbeitstitel des Ortes: Krähenwacht. Ungefähr doppelte Höhe eines großen Hexenwaldbaums als Ausgangspunkt; endgültige Größe anhand von Ellie, Turm und Kamerabild prüfen. Breite, asymmetrische Krone, gebrochene Spitze, schwere verdrehte Wurzeln und gut erkennbare Sitzäste. Die Silhouette muss bereits durch den Nebel auffallen.

Art folgt der bestehenden nativen Pixel-Pipeline: dunkelviolette Rindenspalten, verwittertes Bleichholz, kühles Moos, sparsame Flechten und Pilzkonsolen; gerichtete Texturcluster statt Pixelrauschen. Einzelne alte Schnüre oder Hexenanhänger deuten Esmas Verbindung an, ohne den Turm zu kopieren. Leerenadern konzentrieren sich auf eine Wurzelhöhlung; der Baum selbst ist kein Gegner.

Getrennte Ebenen für Boden/Wurzeln, Stamm, Krone, hängendes Moos, Anhänger und Licht. Langsames Astwiegen, versetztes Moospendeln, seltenes Knarren und wenige fallende Federn. Keine starre Rotation des gesamten Pixelbaums. Krone verblasst bei Verdeckung; Stammkollision entspricht sichtbarem Holz. Genügend offene Fläche vor dem Baum für den späteren Boss, freie Zugänge und keine versteckten Gegner unter der Krone. Standort erst nach Geländeprüfung festlegen, abseits des Turms über einen kurzen erkennbaren Seitenpfad.

Viele Krähen als lebendiger Schwarm: echte Sitzplätze, Putzen, Kopfbewegungen, kurze Astwechsel und gelegentliche kleine Aufflüge. Zahl und Aktivität aus der vorhandenen Vogeltechnik ableiten und begrenzen, statt viele neue unabhängige KI-Figuren einzusetzen. Vögel bleiben unverwundbar und sind kein Kampfziel.

Zwei vorbereitete Zustände: BESETZT und BEFREIT. Besetzt: Krähen sammeln sich unruhig in den oberen Ästen, meiden die Wurzeln, Rufe brechen ab. Befreit: ein kurzer gemeinsamer Aufflug, dann landen die ersten Tiere wieder tiefer; Rufen und Bewegung beruhigen sich. Nicht alle Tiere gleichzeitig verschwinden lassen: der Ort soll auch besetzt als Krähenbaum erkennbar sein.

Ergebnis dieses Schritts: fertiger, animierter Ort in der Welt, Vorschau beider Zustände, vorbereitete Sitz- und Kampfpositionen. Noch keine Quest, Belohnung oder endgültiger Boss. Gegnerpositionen vorbereiten; der Testkampf wird in Schritt 3 aktiviert.

## 2. Esma: Begegnung, Arbeit und Belohnung inszenieren

Zuerst vorhandene Clips und acht Richtungen prüfen: idle, walk, stir und craft existieren bereits im Rig. Nur tatsächlich fehlende Gesten ergänzen, keine funktionierenden Animationen neu erfinden.

Benötigte Szenen: vom Arbeitsplatz zu Ellie wenden; ruhig zuhören und sprechen; zum Baum hinausdeuten; Material aufnehmen und am Tisch arbeiten; zwei kleine Ohrringe prüfen; Ellie das fertige Paar überreichen; danach in den normalen Tagesablauf zurückkehren. Arbeitsclip darf wiederholt laufen, Übergabe und Reaktion sind einmalige Gesten. Passende Hand-/Gegenstandsanker, Schmuck, Licht und kleine Geräusche mitführen.

Esma wirkt mit dem Wald vertraut, trocken und eigenwillig. Sie nimmt Ellies Schrecken ernst, kennt aber den Unterschied zwischen Nebelbildern und echten Eindringlingen. Keine lange Erklärung am Stück: wenige Sätze und deutliche Gesten. Während Ellie unterwegs ist, arbeitet Esma sichtbar an den Ohrringen. Keine reale Wartezeit und kein Herstellungs-Timer als zusätzliche Hürde.

Ergebnis dieses Schritts: alle Begegnungs- und Übergabegesten separat vorführbar, sauberer Wechsel zwischen Dialog und Tagesablauf. Noch keine feste Story-Verknüpfung.

## 3. Quest als abgeschlossener Entwicklertest

Start ausschließlich über ENTWICKLER → QUEST-TESTS → ESMAS EINSTIEG. Kein automatischer Start beim Betreten des Walds, keine Verknüpfung mit der Hauptquest. Ein klar gekennzeichneter Neustart setzt nur diesen Test zurück, nicht andere Quests oder die Welt. Keine erzwungenen Autosaves. Voraussetzungen und optionale Testausrüstung beim Bau festlegen; den früher geplanten Stufe-5-Zugang nicht ungefragt als Testsperre übernehmen.

### Ablauf

1. **Sprich mit Valdrick.** Er hat südlich der bekannten Wege etwas Ungewöhnliches bemerkt. Seine genaue Beobachtung und der endgültige Wortlaut bleiben offen. Vorschlag: Krähen flogen alle in dieselbe Richtung; aus dem Wald kam danach kein Ruf mehr. Er gibt eine Richtung, kennt aber nicht bereits Esmas ganzen Auftrag.
2. **Untersuche den Waldsaum.** Ellie findet den Hexenwald. Beim echten Gebietsübergang eine kurze Beobachtung zur veränderten Luft und zum Licht. Ein räumlicher Wegpunkt reicht, keine Pfeilkette durch den Wald.
3. **Folge dem alten Weg.** Die erste tatsächlich sichtbare Trugspinne löst Ellies erschrockene Reaktion aus. Trigger an die Halluzination koppeln, nicht an einen blinden Timer. Einmal pro Testlauf; keine Wiederholung nach kurzem Verlassen des Bereichs. Unterwegs zwei bis drei kurze, räumlich ausgelöste Selbstgespräche mit genügend Abstand. Keine blockierenden Dialoge bei echter Kampfgefahr.
4. **Betritt den Hexenturm.** Der geschützte Innenraum bringt einen bewussten ruhigen Moment. Ellie begegnet Esma und erzählt von den Spinnen und dem Nebel. Esma erklärt: Die Bilder des Nebels sind harmlos; die Wesen am Krähenbaum sind echt.
5. **Hilf dem Krähenbaum.** Esma bietet die Ohrringe als Gegenleistung an und beginnt mit der Arbeit. Kein zusätzlicher Sammelauftrag. Der Baum erhält nun ein klares Questziel und eine Wegbeschreibung.
6. **Vertreibe die Leere.** Zunächst drei feste echte Schattenspinnen an getrennten, gut sichtbaren Wurzelpositionen; Zahl datengetrieben und nach Spieltest anpassbar. Alle gehören eindeutig zu diesem Begegnungsdurchlauf. Nur diese Gegner zählen, keine Trugbilder oder zufälligen Nachtspinnen. Keine neue Welle bei Chunk-Neuladen. Der spätere Boss kann diesen Begegnungsblock ersetzen, ohne die Quest neu zu schreiben.
7. **Der Baum atmet auf.** Nach dem letzten echten Gegner kurze Ruhe, gemeinsamer Aufflug, zurückkehrende Rufe und der Wechsel zu BEFREIT. Ellies knapper Kommentar bestätigt den Erfolg. Keine lange Kamerasperre im Kampfgebiet.
8. **Kehre zu Esma zurück.** Esma überreicht einmalig die Ohrringe der Klarheit. Falls der vorgesehene Schmuckplatz noch gesperrt ist, im Test gezielt freischalten; bestehende Plätze nicht ändern. Bei vollem Inventar bleibt die Belohnung abholbar. Nicht automatisch fremden Schmuck ablegen.
9. **Lege die Ohrringe an.** Kurzer Hinweis zum Ausrüsten. Draußen erlebt Ellie den Unterschied: Nebelwirkung und Trugbilder weichen durch den bestehenden Perk. Erst das Anlegen gewährt Schutz, kein heimlicher permanenter Questbonus. Abschluss mit einer kurzen Reaktion, keine weitere Quest erzwingen.

### Fairness und Technik

- Der feste Questkampf ist eine bewusste örtliche Ausnahme von der bisherigen Regel „tagsüber keine echten Kreaturen im Hexenwald“. Keine Änderung der allgemeinen Tagespopulation.
- Vor dem Kampf markiert Esmas Warnung den Unterschied. Echte Spinnen behalten ihre normalen Treffer-, Schatten- und Schadenssignale. Im unmittelbaren Testkampf Trugspinnen und falsche HUD-Werte aussetzen; die Nebelstimmung bleibt. So lernt man die Regeln statt gegen uneindeutige Anzeigen kämpfen zu müssen.
- Questphase, echte Gegner, Befreiung und Belohnung werden vom Host entschieden. Halluzinationen und Ellies Wahrnehmung bleiben spielerlokal. Belohnung pro berechtigtem Spieler genau einmal; kein impliziter Gruppenschutz durch Ohrringe. Mehrspielerbeitritt und Beteiligungsregeln vor Umsetzung explizit festlegen.
- Trennung von Ort, Begegnung und Quest: Der Baum existiert unabhängig; Testgegner werden nur vom aktiven Testauftrag erzeugt. Ein späterer Boss bekommt einen eigenen Begegnungsabschluss, keinen überall fest codierten Spinnenzähler.
- Tod, Rückweg, Turmwechsel, Chunk-Entladen und erneuter Entwicklerstart dürfen weder Gegner noch Belohnungen verdoppeln. Abbruch/Neustart entfernt nur eigene Testgegner und lokale Dialogtrigger. Teststatus klar vom normalen Storyfortschritt trennen.

### Abnahme

Schritt 1: Baum bei Tag/Nacht und mit Nebel prüfen, Silhouette, Verdeckung, Kollision, Sitzplätze, Schwarmkosten und beide Zustände.
Schritt 2: jede Geste in den nötigen Blickrichtungen prüfen; Übergänge, Handanker, Tischkontakt und Rückkehr zum Tagesablauf.
Schritt 3: einmal komplett vom Entwicklerbutton bis zum Anlegen spielen; zusätzlich Tod, Neustart, bereits besiegte Spinnen, volle Tasche, vorhandene Ohrringe, Bereichswechsel und Mehrspielerfälle prüfen. Dialogtexte und Kampfgefühl erst anhand dieses Durchlaufs finalisieren.

## Bewusst später

Endgültiger Boss und mögliche Wiederverwendung des bestehenden rabenartigen Bosses; weitere Geheimnisse/Funktionen des Krähenbaums; reguläre Story-Anbindung und Zugangsstufe. Keine dieser Entscheidungen blockiert die drei Schritte oben.
