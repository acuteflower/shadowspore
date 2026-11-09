# Mornath, Phase 3 "Der Himmel brennt": Konzept

Stand: 2026-11-09. Geschrieben für das Design-Gespräch mit dem Auftraggeber: erst lesen, entscheiden, dann bauen. Alles, was **[gebaut]** heißt, läuft schon (siehe `docs/boss_sky_cleaver.md`); alles andere ist Vorschlag mit Zahlen zum Verwerfen oder Anpassen. Alle Zahlen sind aus dem Code und den Daten gerechnet, **nicht gespielt**.

---

## 1. Was Phase 3 sein soll

Phase 1 ist ein Lesen-Lernen (Federn, Regen, Jagd), Phase 2 ist Raum-Aufteilung (Riss, Zange, Hände, Käfig). **Phase 3 ist Tempo und Druck:** er ist schneller, er jagt aktiv, und der Boden selbst wird zur Waffe. Die Leitlinien:

1. **Er kommt zu dir.** Phase 1 und 2 sind aus der Distanz lesbar; in Phase 3 kommt der Boss auf Spieler zu (Sturzflug), der Pfeiler ist kein sicherer Standort mehr.
2. **Ausweichen ist eine Entscheidung mit Preis.** Der Zugriff lässt sich nur im exakten Moment per Blink (später: Ausweichrolle) umgehen. Blink hat 5 s Abklingzeit, also muss jede Blink-Forderung so getaktet sein, dass er wieder bereit ist.
3. **Belohnung für gutes Spiel.** Wer dem Zugriff entkommt, bekommt ein langes, weiches Fenster (Boss steht müde und offen). Wer getroffen wird, brennt.
4. **Der Raum schrumpft.** Feuer am Boden nimmt Fläche weg. Am Ende brennt alles.
5. **Lesbarkeit zuerst.** Der Boden ist jetzt voller pinker Flammen. Jede Warnung muss sich davon abheben (siehe 8).

---

## 2. Stand: was schon läuft **[gebaut]**

Start der Phase (Druckwelle, 25 % Leben, Schrei, Verwandlung, Boden und letzte Säule brennen, Karte „DER HIMMEL BRENNT“): `docs/boss_sky_cleaver.md`, Abschnitt „phase 3“.

Rotation: `dive, rain, dive, dive, rain`, Pause zwischen den Angriffen 0,55 bis 0,95 s (Phase 2: 0,9 bis 1,5 s). Unter 20 % Leben läuft alles 8 % schneller (`haste` 1,08). Alle Zahlen in `data/enemies.json` unter `fight.p3`.

### 2.1 Angriff 1: der lange Regen („Großflächiger Angriff“)

Sieben Wellen hintereinander, jede eine eigene Form, alle Streifen so breit wie vorher (24 px + 3 pro weiterem Spieler), Schaden **28** (vorher 24), Warnzeit 0,9 s, 0,95 s zwischen den Wellen:

| # | Form | Richtung des Durchlaufs |
|---|------|-------------------------|
| 1 | senkrechte Streifen | links nach rechts |
| 2 | Ringe aus der Arena-Mitte | von innen nach außen |
| 3 | diagonale Streifen, nach links geneigt („\\") | läuft nach links |
| 4 | Ringe, Ursprung 2 (links unten der Mitte) | von außen nach innen |
| 5 | diagonale Streifen, nach rechts geneigt („/") | läuft nach rechts |
| 6 | Ringe, Ursprung 3 (rechts oben der Mitte) | von innen nach außen |
| 7 | waagerechte Streifen | von unten nach oben |

Die Versätze der Streifen kommen aus dem Seed des Angriffs (zufällig, aber auf allen Rechnern gleich). Jede Welle deckt 51 bis 62 % des Bodens ab (gemessen im Test). Dauer ca. 8 s plus 2 s Erschöpfung (er hängt schlaff, rüstungsfaktor 1,5, vorher 1,7). Die Ursprünge der Ringe liegen in `fight.p3.rain.origins` (relativ zum Sonnensigil).

*Anmerkung:* „Diagonal nach links“ habe ich so gebaut: Streifenlinien neigen sich nach links und die Welle wandert nach links. Wenn gemeint war „nur die Wanderrichtung“, ist es eine Zeile in `_rain_waves_final`.

### 2.2 Angriff 2: der Zugriff („Sturzflug“) 

Ablauf, mit den Zahlen aus `fight.p3.dive`:

1. **Anvisieren (0,95 s):** er lehnt sich auf dem Pfeiler nach vorn, Kopf tief, Krallen am Stein, Zittern. Über dem Kopf des Ziels erscheint das Auge (wie bei der Jagd). In dieser Zeit ist er treffbar (Rüstung 0,7).
2. **Sturzflug:** er lässt los, Nase nach unten, Flügel nach hinten. Er fliegt mit 150 px/s an und beschleunigt auf **400 px/s** (Spieler-Sprint 104), in Bodennähe (16 px hoch), mit **lenkendem** Verfolgen (3,4 rad/s): geradeaus weglaufen hilft nicht, ein Blink oder ein enger Haken schon. Er gibt nach 2,6 s auf. Er ist im Flug nicht treffbar.
3. **Aufrichten (0,32 s):** 34 px vor dem Ziel richtet er sich auf, Flügel hoch. Genau jetzt erscheint ein kleiner Ring (Radius 34) am Boden; nach 0,32 s schlagen die Flügel zusammen. 0,32 s sind zu kurz zum Weglaufen (Sprint ca. 33 px), nur ein Blink (96 px) oder ein perfekt getimter Seitwärtsschritt kommt raus.
4. **Treffer:** **36 Schaden, Rückstoß 160, dazu Verbrennen (5 s).** 
5. **Danach:** er steht müde da: **1,3 s offen, Rüstung 1,5** (vorher Phase-1-Jagd: 2,2 s bei 2,0). Hat der Zugriff **niemanden** getroffen, bleibt er **2,4 s offen bei Rüstung 2,0**. Dann fliegt er zum Pfeiler.

Co-op: er jagt den ausgewählten Spieler (nie zweimal denselben hintereinander, wie bei den anderen Angriffen); der Ring wächst pro weiterem Spieler um 6 %, damit zwei Nebeneinanderstehende nicht beide entkommen.

*Abstand zwischen zwei Sturzflügen (Blink-Regel):* `dive, dive` ist nur fair, wenn der Blink wieder bereit ist. Gerechnet: Erschöpfung 1,3 s + Rückflug ca. 2 s + Landen 0,5 s + Pause ≥ 0,55 s + Anvisieren 0,95 s + Anflug ca. 1 s ≈ 6,3 s zwischen den beiden Zugriffen, Blink-Abklingzeit 5 s. **Das ist knapp (1,3 s Reserve) und gehört im Spiel gemessen.** Wird die Ausweichrolle gebaut, entfällt die Regel.

### 2.3 Das Effektsystem und „Verbrennen“ **[gebaut]**

Neues festes System: `StatusEffects` (Kind `Effects` jedes Spielers, `src/components/status_effects.gd`), Daten in `data/status_effects.json`.

- **Verbrennen:** 4 s (Zugriff setzt 5 s), alle 0,5 s **2 % des Maximal-Lebens** (mindestens 2), also 4 % pro Sekunde, bei 100 Leben 16 bis 20 Punkte pro Anwendung. Erneutes Verbrennen **verlängert** nur, es stapelt nicht. Tick-Schaden ohne Rückstoß, ohne Zucken, ohne Schutzzeit, unterbricht nichts (`HealthComponent.take_tick`). **Wasser löscht** (jede Oberfläche mit `submerge`), im Wasser entzündet man sich nicht.
- Host entscheidet, Peers zählen selbst herunter (kein Dauerverkehr). Tod löscht alle Effekte.
- Optik: pink-violette Flammen am Körper (`BurnFx`, dieselbe Flamme wie am Boss), HUD-Marke „VERBRENNEN“ mit Lichtriss als Restzeit über dem linken Ende der Lebensranke (`StatusTags`), kleine rosa Zahlen für die Ticks.
- Erweiterbar: neuer Eintrag in der JSON + ein Fall in `_show` für die Optik. Vorgesehen sind Gift, Frost (langsamer), Blutung, Betäubung, „Verwundbar“ (mehr Schaden), und Gegenseiten wie „Schutz vor Feuer“ (Ausrüstung, Trank). Ein `scale`-Wert pro Anwendung erlaubt schwächere Quellen (Bodenfeuer) und den Schadensfaktor des Bosses.

---

## 3. Weitere Angriffe (Vorschläge)

Ziel: Phase 3 hat **sieben** Angriffe, davon zwei neu gebaut. Vorschlag für vier weitere, jeder mit eindeutigem Gegenmittel, jeder nutzt Dinge, die es schon gibt (Warnzonen, Federn, Ringe, Marker). Reihenfolge nach Aufwand und Wirkung.

### A. „Glutfeld“ (Feuerfedern, Bodenfeuer)  *klein, sehr wirksam* **[gebaut]**
Er wirft 3 bis 5 Federn (mehr bei mehr Spielern) auf die Positionen der Spieler. Jede steckt sich nach 0,6 s fest und **entzündet nach 0,9 s ein Feuerfeld** (Radius 26), das **6 s brennt** und beim Betreten verbrennt (Effekt mit `scale` 0,6, kein Direktschaden). Felder nehmen Platz weg, mehrere Würfe füllen die Arena nach und nach. 
- Gegenmittel: laufen, Pfade planen. Das Feld ist rot warnend, bevor es brennt.
- Grundlage: der gebaute SHOT (Feder + Fuse + Zone). Neue Zone mit Dauer und `burn`.
- Gefahr: zu viel Bodenfeuer plus Flammen-Deko = unlesbar. Deshalb brennende Felder dunkler-roter Ring, damit sie sich von der Deko abheben.

### B. „Himmelssplitter“ (Lichtsäulen)  *mittel* **[gebaut]**
Fünf Lichtsäulen schlagen nacheinander ein, jede dort, wo ein Spieler **vor 1 s** stand (Wegrennen in Bewegung reicht nicht, Stehenbleiben wird bestraft). Jede Säule: Warnring 0,9 s, Radius 30, 30 Schaden, hinterlässt kurz Feuer (3 s). Die Reihenfolge ist ein Muster (Kreis um die Arena-Mitte oder Zickzack), das man lernen kann.
- Gegenmittel: in Bewegung bleiben, Muster lesen.
- Grundlage: Verlauf des Spielers wie bei der Jagd (`hist`), Ringe wie im Regen.

### C. „Brandmal“ (Co-op-Mechanik, Solo ein Test)  *mittel* **[gebaut]**
Ein Spieler wird markiert (großes rosa Siegel über dem Kopf, in der HUD-Sprache). Nach **4 s** explodiert das Mal: Ring Radius 70, 34 Schaden + Verbrennen für **alle im Ring**. Solo: weglaufen aus dem eigenen Feuer, also in die freie Fläche. Zu zweit: sich vom Partner trennen. Zu viert: Markierter geht an den Rand, die anderen bleiben weg.
- Gegenmittel: Abstand. Der Marker zeigt den Radius mit.
- Belohnung: wer die Explosion in einer „kalten Stelle“ (siehe 4.3) auslöst, nimmt keinen Brand.
- Sicherheit: nie auf den Spieler zielen, der gerade den Zugriff hatte (ein Dodge nach dem anderen ist unfair).

### D. „Doppelsturz“ („Zange“)  *klein, nur ab 2 Spielern*
Ab 2 Spielern stürzt er auf einen Spieler an, zeitgleich schießt aus der Gegenrichtung ein Flügelschlag-Schatten (Illusion, die Federn spuckt) auf den zweiten. Zwei Sturzflüge auf zwei Ziele versetzt um 0,6 s. So teilt er Spieler auf und verlangt Absprache.
- Grundlage: der gebaute Sturzflug mit zweitem Ziel; die Phase-2-Idee „Schattendoppel“.

### E. Alternativen, falls etwas nicht gefällt
- **„Aschesturm“:** 2 bis 3 langsame Wirbel (Radius 24), die zu den Spielern driften und beim Berühren verbrennen.
- **„Lichtbruch“:** ein Schrei in einem 100-Grad-Kegel, Rückstoß + Verbrennen, dahinter bleibt kein Feuer. Nützlich als kurzer, leichter Zwischenangriff in der Rotation.

### Wie A, B und C gebaut sind (Stand 2026-11-09)

Alle drei hängen in `fight.p3` (`data/enemies.json`), die Rotation ist jetzt `dive, rain, glut, splitter, dive, mark, rain, glut, dive, splitter, mark, rain` (zwischen zwei Zugriffen immer mindestens drei andere Angriffe, Blink-Regel). Feuer und Licht zeichnet und hurt die neue Klasse `FireArena` (`src/entities/enemies/fire_arena.gd`, Kind des Bosses, `field.blaze`); die Warnringe bleiben die des `FeatherField`.

- **Glutfeld (`glut`):** Aufladen 0,7 s, Ziel sperrt 0,3 s vor dem Wurf. 3 Federn (+1 je weiterem Spieler, höchstens 5) im Abstand 0,22 s; die erste auf jeden Spieler, die übrigen 38 bis 92 px um sie herum. Ring warnt ab dem Zielen, nach dem Einschlag +0,9 s fängt der Boden Feuer (Radius 26, 6 s, Verbrennen mit Stärke 0,6, kein Direktschaden): dunkler verkohlter Fleck mit rotem Rand, Flammen am Rand und in der Mitte, weißes Aufflammen beim Zünden. Er steht danach 1,0 s offen.
- **Himmelssplitter (`splitter`):** er steigt auf (Schweben wie im Regen), 5 Säulen (+1 je weiterem Spieler, höchstens 8) im Abstand 0,5 s. Jede Säule wird dort angekündigt, wo der gewählte Spieler **vor 1 s** stand (Host führt Spuren, alle 0,1 s ein Punkt), jede zweite auf der **gegenüberliegenden Seite der Arena-Mitte** (Spiegelung): das ist das lernbare Muster. Ring 0,9 s, Radius 30, 30 Schaden; vorher fällt eine Haarlinie aus Licht, beim Einschlag eine zackige Säule aus Weiß und Rosa mit Funken und Druckring; danach brennt der Boden 3 s (Stärke 0,6). Danach hängt er 1,8 s erschöpft (Rüstung 1,5).
- **Brandmal (`mark`):** er wirft eine Feder auf einen Spieler (nie den vom letzten Angriff, wenn es andere gibt), ein Siegel dreht sich über dem Kopf und zählt von 4 herunter (rosa Ring, Flammenzeichen, Zahl, Lichtriss; die Marke steht auch als Effekt „BRANDMAL“ in der HUD-Leiste). Der Radius (70) wandert als gepunkteter Kreis mit ihr. **1,2 s vor dem Ende** sinkt das Siegel an ihrer Stelle in den Boden, ab da gilt der Ring (rote Warnung, Flammen wachsen am Rand), dann Explosion: 34 Schaden, Verbrennen 5 s für alle im Ring. Er steht in der ganzen Zeit offen (Rüstung 1,0).
- **Brennender Rand:** unter 20 % Leben entzündet sich ein 22 px breiter Streifen am Rand der Fläche dauerhaft (Brüllen, Druckring, 1,6 s zum Zünden), Verbrennen mit Stärke 0,5, 1,6 s Nachbrennen.
- **Urteil II:** in `fight.phases` die dritte Stufe bei 10 % (Säule 2, die letzte, brennende); Zahlen in `fight.judgement2`: 22 s, Säule 420 (+60 % je weiterem Spieler), Druckwelle alle 4 s mit Feuerkranz (Verbrennen 4 s). **Der ganze Boden brennt** (Stärke 0,5: bei 100 Leben 1 Punkt je 0,5 s), **drei kalte Inseln** (Radius 36, schrumpfen alle 6 s um 16 %, mindestens 30 %), 185 px von der Säule: türkise Reste des alten Lichts, dort brennt nichts und das Verbrennen erlischt. Bricht die Säule, erlischt das Feuer, er liegt (Rüstung 2,0) und kann ohne Zwischenfinisher getötet werden; steht er nach 14 s noch, schreit er einmal (Ring 120, 24 Schaden, Verbrennen). Scheitern wie Urteil I (alle sterben, Neustart am Anfang von Phase 3). **Nicht gebaut:** eigener Checkpoint vor dem Urteil, Skalierung nach Spielerzahl, kalte Stellen nach ausgewichenen Angriffen, Belohnung des Brandmals für kalte Stellen.

### Vorgeschlagene Rotation (Beispiel)
`dive, rain, glutfeld, dive, himmelssplitter, brandmal, rain, dive+dive (ab 2)`. Gewichtung so, dass zwischen zwei Blink-Forderungen (Zugriff) immer mindestens 6 s liegen. Unter 20 % Leben: kürzere Pausen und Kombinationen (`glutfeld+` startet einen Sturzflug nach 0,8 s).

---

## 4. Der Boden und das Ende der Phase

### 4.1 Entwicklung des Bodens in Phase 3 **[gebaut: Rand bei 20 %, ganzer Boden im Urteil II]**
Der Boden brennt jetzt schon optisch (pinkes Licht, Flammen). Vorschlag, daraus **Spielfläche** zu machen, in Schritten:
- **Phase 3 Beginn:** nur Deko (so jetzt).
- **Bei 20 % Leben:** ein Ring am Rand der Fläche entzündet sich (Breite 22 px) und brennt **dauerhaft** (Verbrennen, `scale` 0,5). Die Fläche schrumpft um ca. 30 %.
- **Im Urteil II:** der gesamte Boden brennt (siehe 4.2).
Technik: eine Schicht aus Zonen (`FeatherField`) oder besser ein eigenes Brandfeld (Raster 8 px, Maske aus der Bodenzone), das Spieler testen. Die Optik gibt es (Flammen auf dem Licht).

### 4.2 Urteil II (Ende von Phase 3) **[gebaut, ohne Spielerzahl-Skalierung]**
Wie das Urteil in Phase 2, aber härter:
- **Zeit 22 s** (vorher 28), **Säulen-HP rund 420** (vorher 240; +60 % pro weiterem Spieler statt +70 %): das ist **2,2 mal so viel Schaden pro Sekunde** wie im ersten Urteil (8,6 HP/s auf 18,9 HP/s). Gerechnet mit der Annahme, dass etwa 55 % der Zeit wirklich geschlagen wird.
- **Der gesamte Boden brennt dauerhaft** bis zum Ende des Urteils: jeder Tick, den man auf der Fläche steht, hält das Verbrennen am Leben, Tick-Stärke **halbiert** (`scale` 0,5, also 1 % pro 0,5 s = 2 HP/s bei 100 Leben, in 22 s ca. 44 Punkte). Sonst wäre der Boden ein Todesurteil allein.
- Der Pfeiler wehrt sich alle **4 s** (vorher 5): Druckwelle + Federkranz **mit Feuer**.
- **Kalte Stellen:** wo ein Zugriff oder eine Welle ins Leere gegangen ist, bleibt ein Fleck „kalter Boden“ (Radius 28, 8 s): kein Feuer, löscht das Verbrennen. Taktik: dort kurz Atem holen. In Urteil II gibt es 3 feste kalte Inseln um den Pfeiler (Radius 36), die alle 6 s kleiner werden.
- Ausgang wie Urteil I: Pfeiler bricht = er stürzt, Finisher, letzte Etappe. Scheitern = alle im Radius sterben, Neustart bei Phase 3 (Checkpoint vor dem Urteil, nicht am Beginn der Phase).
- **Danach** (Vorschlag): er liegt brennend am Boden, Boden erlischt, Rüstung 2,0, Spieler können die letzten **~10 %** (ca. 90 HP) herunterschlagen; steht er nach 14 s noch, erhebt er sich einmal zu einem letzten Schrei (Ring, 24 Schaden), danach bleibt er liegen. Tod: Absturz-Animation (existiert), Feuer am Boden erlischt über 4 s (existiert), Beute (Platzhalter).

Offene Zahl: **wo** in der Lebensleiste das Urteil II liegt. Vorschlag **10 %** (nach dem Muster 66,7 / 33,3 / 10).

### 4.3 Kalte Stellen als Belohnung (neues kleines System)
Kleiner Bodeneffekt, der mit dem Ausweichen verknüpft ist: wer einem Zugriff entkommt, gibt dem Boden an der Stelle des Rings Frost. Er löscht Verbrennen und schützt vor Bodenfeuer. Er zeigt dem Spieler, **dass** er etwas richtig gemacht hat. Aufwand klein (Zone mit Oberfläche „Reif“, `StatusEffects.apply` verweigern, `clear`).

---

## 5. Anpassung an die Spielerzahl

Heute: `health_scale` und `damage_scale` bleiben 1 (die Arena beschwört ihn ohne Skalierung); nur Streifenbreite, Federanzahl, Ringgröße und Urteil-Säule skalieren mit `_extra()` (Spieler im Umkreis 420 px).

### 5.1 Zählen
- `n` = lebende **Teilnehmer** im Umkreis von 420 px um die Arena-Mitte, **bei Beschwören** gezählt und **an jeder Phasengrenze** neu (1 / 2 / 3).
- Wer später dazukommt, ändert die Werte erst bei der nächsten Grenze (kein Springen der Lebensleiste mitten im Angriff). Verlässt jemand die Arena für länger als 8 s, zählt er nicht mehr.
- Beim Wechsel bleibt der **Anteil** der Lebensleiste gleich (Prozent), nicht der absolute Wert.

### 5.2 Formeln (Vorschlag)

| Größe | n=1 | n=2 | n=3 | n=4 | Formel |
|-------|-----|-----|-----|-----|--------|
| Boss-Leben | 1,00 | 1,80 | 2,60 | 3,40 | `1 + 0,8 (n-1)` |
| Boss-Schaden | 1,00 | 1,10 | 1,20 | 1,30 | `1 + 0,10 (n-1)` |
| Säulen-HP (Urteil) | 1,00 | 1,60 | 2,20 | 2,80 | `1 + 0,6 (n-1)` |
| Brand-Tick | 1,00 | 1,00 | 1,00 | 1,00 | bleibt (Brand ist pro Kopf) |
| Warnzeiten | 1,00 | 1,00 | 0,95 | 0,92 | ab 3 minimal kürzer |

Begründung: bei zwei Spielern verdoppelt sich ungefähr der Schaden, aber nur ~80 % davon landet, weil beide ausweichen müssen und die Treffer-Fenster gemeinsam sind (alle stehen am selben Pfeiler). Der Schaden des Bosses steigt nur wenig, weil mehr Spieler die Treffer **verteilen** (Ziele werden abwechselnd gewählt). Die Urteil-Säule skaliert flacher als der Boss, weil alle gleichzeitig auf **einen** Stein schlagen.

### 5.3 Mechanik statt Zahlen
Die wichtigeren Anpassungen sind nicht Zahlen:
- **Regen:** Streifenbreite +3 px pro Spieler (gebaut), Wellen bleiben 7.
- **Zugriff:** Ring +6 % pro Spieler (gebaut). Ab 3 Spielern **zwei Sturzflüge** gleichzeitig auf verschiedene Ziele (Angriff D).
- **Brandmal:** ab 2 Spielern ein Mal pro Durchgang, ab 4 zwei Male (verschiedene Ziele).
- **Glutfeld:** Anzahl Federn `3 + n`, nie mehr als 7.
- **Ziele wählen:** keinen Spieler zweimal hintereinander; wer gerade getroffen wurde oder brennt, wird bei **Zugriff** und **Brandmal** nicht gewählt (Schutz vor Kettenverlusten).
- **Gefallene:** ein toter Spieler kann nicht zurück, bis der Kampf endet (bisher). Vorschlag: **Wiederbeleben** am Pfeiler-Fuß durch einen lebenden Spieler (E gedrückt halten 2,5 s, 25 % Leben) nur während des Urteils nicht erlaubt. Sonst bleibt Co-op bei Tod hart.

### 5.4 Stärke der Spieler
Der Boss soll sich an die **Waffenstufe** anpassen lassen (`EnemyScaling` aus der Nacht-Logik: Stufe + Waffenstärke). Aktuell sind die 900 HP nur mit der Test-Klinge „Leerenklinge“ (30 Schaden) sinnvoll; mit Starter-Schwert (5) wären es grob 180 Treffer. **Entscheidung nötig:** welche Waffe ist der Maßstab für Boss 1 (z. B. geschmiedetes Schwert plus eine Verzauberung ca. 14 bis 16 Schaden)? Dann `max_health = Ziel-Kampfdauer × DPS_Soll × Aktivzeit`. Vorschlag: Kampfdauer **8 bis 10 Minuten** solo, Aktivzeit 45 %.

---

## 6. Ausbesserungen in Phase 1 und 2 (aus der Durchsicht)

Dinge, die mir beim Lesen des ganzen Kampfes aufgefallen sind und die Phase 3 mittragen sollte:

1. **Nahkampf am Pfeiler ist fast immer möglich.** Er sitzt auf dem Pfeiler und ist in fast allen Aktionen treffbar; als Gegengewicht gibt es nur die Druckwelle (alle 5 s, wenn man 0,9 s lang nah steht). Vorschlag: in Phase 3 **Feuerstoß am Pfeiler-Fuß** alle ~8 s (Radius 40, Brandeffekt), und das Auslösen der Druckwelle auf 0,6 s Nähe senken. Oder: die Zugriffsfenster als Hauptweg zum Schaden machen.
2. **Heilen im Kampf.** Ein Spieler hat 100 Leben und steht nach 4 Treffern; gebaut sind nur Beeren (5 bis 18 Leben über Zeit). Vorschlag: **Heilfunken**: ein ausgewichener Zugriff erzeugt einen Funken, der beim Einsammeln 12 % Leben über 6 s heilt. Belohnt das Ausweichen, ist Co-op-teilbar.
3. **Skalierung und Waffenmaßstab** (siehe 5).
4. **Keine Geschichte.** Es gibt keine Dialoge, keinen Quest-Hook, keinen Trigger nach dem Tod. Vorschlag: Valdric-Zeilen (Dossier `docs/enemies/boss_mornath.md`) als Sprechkasten-Barks bei Phasenwechseln; Flag `mornath_defeated`.
5. **Dossier und Spiel passen nicht zusammen.** Das Dossier beschreibt Lärm-Sturzflüge, das Spiel Federn und Himmelsriss. Phase 3 (Feuer, Sturz) steht dem Dossier näher als Phase 1. Vorschlag: Dossier überarbeiten oder bewusst zur „früheren Fassung“ erklären.
6. **Blink-Abhängigkeit:** der Zugriff verlangt Blink alle ~6 s; ohne Blink-Bereitschaft (Abklingzeit, Wasser, Rand) ist er nicht ausweichbar. Entweder die Ausweichrolle zuerst bauen, oder die erste Version mit einer Regel „nie, wenn Blink noch auf Abklingzeit“ abfragen (der Boss kennt `blink.cooldown_left` des Ziels und wählt dann einen anderen Angriff).
7. **Lesbarkeit:** viel Pink, viel Flamme, Glitch-Aura. Regeln: Flammen der Deko unter Warnzonen zeichnen; Warnzonen weiß-heller; Glitch-Aura (`BossAura`) in Phase 3 nicht stärker als 1,0; Option „Weniger Flackern“ in den Einstellungen.

---

## 7. Umsetzungsplan (Vorschlag der Reihenfolge)

| Schritt | Inhalt | Aufwand | Status |
|---------|--------|---------|--------|
| 1 | Übergang, Boden/Säule brennen | – | gebaut |
| 2 | Effektsystem + Verbrennen, Regen (lang), Zugriff | mittel | **gebaut** |
| 3 | Glutfeld, Lichtsäulen (Himmelssplitter) | klein/mittel | offen |
| 4 | Skalierung nach Spielerzahl (Beschwören, Phasengrenzen) | klein | offen |
| 5 | Boden als Brandfeld (Rand ab 20 %, später komplett) + kalte Stellen | mittel | offen |
| 6 | Urteil II + Ende des Kampfes + Checkpoint | mittel | offen |
| 7 | Brandmal, Doppelsturz (Co-op) | mittel | offen |
| 8 | Ausweichrolle (Leertaste), Heilfunken, Waffenmaßstab, Barks | groß | offen |

## 8. Offene Fragen

1. Wo liegt Urteil II (vorgeschlagen **10 %**)?
2. Boden-Brand: Rand ab 20 % oder erst im Urteil?
3. Welche Waffe ist der Maßstab für Boss 1?
4. Soll der Zugriff warten, bis der Blink wieder bereit ist, oder erst die Ausweichrolle gebaut werden?
5. Co-op: Wiederbeleben im Kampf ja oder nein?
6. Gefallen die vorgeschlagenen Namen (Glutfeld, Himmelssplitter, Brandmal, Doppelsturz)?
