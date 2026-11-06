# Spielbeginn: Stand und nächster Abschnitt

**Aktualisierung: Der Ritterabschnitt ist inzwischen umgesetzt.** Aktuelle Position, Ablauf und Prüfungen stehen in [Ritterfund und Angriffseinführung](knight_encounter.md). Der untenstehende ursprüngliche Plan bleibt als Referenz erhalten.

## Jetzt umgesetzt

- Neue Weltfiguren starten mit 10 % Leben und dem vorhandenen Verletztenzustand: Hinken, eingeschränktes Tempo, kein Sprint, Blut/Blässe und Wundrand. Das gilt auch beim Überspringen der Kanal-Introanimation. Ein geladener Spielstand stellt seine gespeicherte Gesundheit wieder her.
- Hotbar, Lebens-/Ausdaueranzeige, Uhrzeit, Währung und das an der Hotbar hängende Blink-Symbol bleiben im frühen Spiel verborgen. Quest und Schleichhinweis bleiben erhalten. Leben und Ausdauer folgen stets der Hotbar-Sichtbarkeit. Der rote Wundrand und die Blutdarstellung sind bereits während der Gulli-Animation aktiv und werden zusammen mit der Welt aus der Schwarzblende sichtbar. Das gilt auch nach der Intro-Einblendung, nach Dialogen und beim Laden. Konfiguration unter `ground.story_start`; eine spätere explizite Questfreigabe `hud_unlocked` ist vorgesehen, wird aktuell von keinem Storyschritt gesetzt.
- Die beiden Wächter stehen jetzt rund 124 px früher am Pfad, Mittelpunkt relativ zum Weltstart `(100,784)`, Positionen `(59,833)` und `(141,735)`. Sie stehen auf ebenem Gelände und bleiben etwa 64 px seitlich von der Durchgangslinie entfernt. Sichtweite normal 92 px, schleichend 46 px. Die bestehende Freihaltezone entfernt auch den störenden Bewuchs direkt an den neuen Wächtern, darunter den Baum an der Passage.
- Der Dialog-/Schleichhinweis wird früher ausgelöst: Annäherung bei Tile `(465,661)`, Schleichziel hinter den versetzten Wächtern bei `(478,674)`. Nachfolgende Abzweigungs-/Schildschritte sind derzeit unverändert.

## Ursprünglicher Ritter-Plan (inzwischen umgesetzt)

### Ort und Questführung

Nach der Schleichpassage führt Ellie der Weg weiter zum Fundort aus Screenshot 2/3. Der sichtbare Positionshinweis verankert diesen Abschnitt ungefähr bei Tile `(499,685)`. Das Questziel liegt zunächst **auf dem Weg** bei dieser Stelle; der Ritter liegt wenige Schritte rechts/östlich davon auf der ebenen Wiese. Die genaue Sitzposition wird beim Einbau gegen den tatsächlich gebackenen Pfad, Kollision und Blickwinkel geprüft. Nicht auf die Klippe links setzen. Die Blütenbäume südlich dürfen den Fund nicht verdecken.

Der bisherige direkte Schritt „Erreiche die Abzweigung“ wird dann zunächst durch „Folge dem Pfad weiter“ zum Fundabschnitt ersetzt. In Sichtnähe wechselt die Aufgabe zu „Untersuche den Ritter“. Abzweigung und Wegweiser folgen erst nach diesem Abschnitt. Die Quest wird **jetzt noch nicht umgeleitet**, damit sie nicht zu einem noch fehlenden Interaktionsobjekt führt.

### Inszenierung

Ein verstorbener Ritter sitzt zusammengesunken an einem umgefallenen, verwitterten Baumstamm neben dem Weg. Der Stamm liegt flach/diagonal und ist als umgefallenes Holz erkennbar. Matte beschädigte Rüstung, schlaffe Haltung, Kopf geneigt, Hand vom Körper abgesunken. Die Leere hat eine Körper-/Rüstungsseite leicht angefressen: dunkle violette Fehlstellen und wenige schwache Adern, ohne Rauch oder Nebel. Eine ruhige Szene; keine Wiederbelebung und kein Angriff.

Der Fund bleibt gegenüber Ellies 42-px-Sprite maßstäblich. Die wichtigen Konturen – Kopf, Brust, Hand und das Schwert – müssen im 640×360-Bild lesbar sein. Lokale Vegetation nur so weit freihalten, dass Ellie auf dem Weg die Silhouette erkennt und an den Ritter herantreten kann.

### Untersuchen und Schwert

- In Reichweite erscheint der bestehende Interaktionshinweis mit der tatsächlich gebundenen E-/Interaktionstaste: „Ritter untersuchen“.
- Die Inspektion ist einmalig, vom Host bestätigt. Das vorhandene `sword_basic` („Einfaches Schwert“) fällt als echtes Item vor den Ritter, mit kleinem Metalllaut und kurzer Fallbewegung.
- Normales Aufheben und Ausrüsten verwenden. Das Schwert ist laut bestehendem Itemschema eine **Haupthandwaffe**, kein Hotbar-Item. Keine neue Waffenart oder erfundenen Werte.
- Inspektion, ausstehende Beute und Erhalt speichern; erneutes Untersuchen oder Laden darf keine Duplikate erzeugen und kein noch nicht aufgenommenes Schwert verlieren. Auch ein volles Inventar darf keinen Verlust verursachen. Die bisherige SaveGame-Datei speichert allgemeine Weltdrops nicht: dafür ist beim Einbau ein gezielter, persistenter Story-Beutestatus nötig.

### Ellie-Dialog, andere Variation

Nach der Inspektion/Schwertfreilegung: verletzte Ellie, aber mit nachdenklicher/entschlossener Variation statt der Schleichwarnung. Ruhiger Blick zum Ritter, anschließend zum Schwert; weiterhin verletzt, keine Heilung durch den Fund.

Vorgeschlagene Zeilen:

> „Was sind das nur für Spinnendinger …?“
>
> „Du hast es also auch nicht geschafft.“
>
> „Das Schwert wird mir bestimmt noch nützlich sein.“

Die zweite Zeile ist ein optionaler Vorschlag. Für die finale Umsetzung kann der Dialog auf die erste und dritte Zeile beschränkt werden. Nach dem Dialog lautet das Ziel gegebenenfalls „Nimm das Schwert“, bis es aufgenommen wurde.

### Einführung in die dreistufige Angriffskette

Erst sobald das Schwert aufgenommen und ausgerüstet ist, erscheint eine Karte im selben Stil wie der Schleichhinweis. Das bestehende Einhandschwert hat bereits drei Stufen: **Hieb → Gegenhieb → Stich**. Die letzte Stufe hat laut `weapon_classes.json` mehr Schaden und Reichweite.

Vorgeschlagener Hinweis:

> ANGRIFFSKETTE
>
> Angriffstaste drücken: Hieb.
>
> Im Rhythmus erneut drücken: Gegenhieb, dann Stich.
>
> Eine längere Pause beginnt die Folge von vorn.

Die Karte zeigt die aktuelle gebundene Angriffstaste, darunter drei kleine Fortschrittsmarken. Fortschritt zählt bestätigte, tatsächlich ausgeführte Kombostufen der ausgerüsteten Waffe; bloße Mausklicks zählen nicht. Bei Abbruch läuft die Demonstration wieder ab Stufe 1. Für diese Einführung ist noch kein Gegner oder Treffer erforderlich: die Bewegung soll gefahrlos ausprobiert werden können, solange Ellie verletzt ist. Beim ersten vollständigen Dreierschritt blüht die Karte auf und zieht sich zurück, wie die Schleichkarte.

Danach führt „Hilfe finden“ weiter zur Abzweigung bzw. zum Wegweiser. Wann Uhr, Währung und übrige Hotbar eingeführt werden, bleibt offen; dieser Abschnitt schaltet sie nicht stillschweigend frei.

## Abnahme beim späteren Einbau

Fund vom Weg aus sichtbar, erreichbare Inspektionsposition, keine blockierte Passage; einmaliges Schwert auch bei vollem Inventar und Speichern vor/nach Inspektion, Drop und Aufnahme; Dialog nur einmal; Fortschritt nach echtem Hieb/Gegenhieb/Stich; Verletzung und bisheriger Questfortschritt bleiben erhalten. Neuer Interaktionsgegenstand und Drop hostautoritativ, einschließlich später beitretender Mitspieler.
