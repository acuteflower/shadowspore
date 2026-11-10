# Hexenwald: Nebel, Halluzination und der Talisman der Hexe (Konzept)

Stand 2026-11-10. **Nichts davon ist gebaut.** Ergänzt `docs/hexenwald_konzept.md` (Stufe 3 "Stimmung" und Stufe 7 "Geschichte"). Der Hexenturm und die Hexe selbst kommen danach und sind hier nur so weit beschrieben, wie der Nebel sie braucht.

## 1. Die Idee in drei Sätzen

Im Hexenwald liegt ein Nebel, der nicht nur die Sicht nimmt, sondern den Kopf: Wer ihn atmet, ist **HALLUZINIERT** und sieht Dinge, die nicht da sind, bis hin zu Schattenwesen, die angreifen und im Schlag zerfallen. Der Wald ist dadurch kein Gebiet, das man mit besserer Ausrüstung besiegt, sondern eines, dem man nicht trauen kann. Erst der Talisman der Hexe macht den Kopf klar und drückt den Nebel um Ellie weg: der Wald, der vorher gelogen hat, wird lesbar, und das ist die Einführung der Talismane.

Leitsatz für jede Einzelentscheidung: **Der Nebel lügt, aber er tötet nicht.** Trugbilder kosten Nerven, Ausdauer und Aufmerksamkeit, nie Leben. Gefährlich wird der Wald, weil zwischen den Lügen auch Echtes steht.

## 2. Der Nebel (Optik)

- **Derselbe Nebel wie in der Nacht, nur hexengrün und auch am Tag.** `night_fog.gdshader` kann schon alles Nötige: Bänke in Weltkoordinaten, Lichtkreise drücken ihn weg, eine Lichtung um die Heldin. Im Hexenwald bekommt er eine zweite Quelle für seine Stärke: `BiomeBlend.amount_at(Kamera)` (0 auf allem Altland, wächst über 48 Tiles beim Hineingehen). Kein neuer Shader, ein Uniform mehr für die Tönung (kaltes Graugrün, in den dichten Stellen ein Hauch Hexengrün `#a8ff6a`).
- **Leicht, nicht blind.** Zielbild: man sieht etwa 10-12 Tiles klar, dahinter werden Stämme zu Schatten. Die Hexenulmen mit ihren glimmenden Gesichtern sind dann genau das, was man als Erstes aus dem Nebel kommen sieht.
- **Er lebt.** Langsame Schwaden gegen den Wind, um Fluchsilber-Felsen und Totenkerzen dünner (die leuchten ihn weg wie Stadtlampen), über dem Tümpel dichter. Nachts dichter und mit dem Nachtnebel addiert, bei Neumond am dichtesten.
- **Dauerdämmer.** Über dieselbe Maske wird das Tageslicht gedämpft (Sonnenflecken und Lichtschäfte aus, `g_gloom` gibt es schon), damit Nebel und Licht zusammenpassen.
- **Kosmetisch und lokal** wie der Nachtnebel: jeder Peer rechnet ihn selbst, nichts geht übers Netz.

## 3. Der Effekt HALLUZINIERT

Läuft durch `StatusEffects` wie VERBRENNEN, als dritter Eintrag in `data/status_effects.json` (`hallucinated`, Name `HALLUZINIERT`, Farbe Hexengrün, kein Schaden).

- **"Permanent" ohne neuen Mechanismus:** der Host frischt den Effekt jede Sekunde auf, solange ein Spieler im Hexenwald steht (`PropGenerator.is_bare` bzw. Nebelmaske über 0,35) und nicht geschützt ist. Wer hinausgeht, ist ihn nach ~8 s los (der Kopf klart nach). `apply()` frischt heute schon auf, statt zu stapeln.
- **HUD:** das Schild in `StatusTags` zeigt keinen ablaufenden Balken, sondern pulsiert langsam (ein Auge, das sich öffnet und schließt). Beim ersten Mal eine Tutorialkarte ("DER NEBEL ZEIGT DIR DINGE. NICHT ALLES IST WAHR.").
- **Tiefe statt Schalter:** ein lokaler Wert **Trug** 0..1 wächst mit der Zeit im Nebel (voll nach ~90 s) und mit der Nebeldichte, fällt draußen schnell. Er steuert, *was* man sieht (Abschnitt 4). Am Waldrand ist man halluziniert, merkt aber fast nichts: der Wald lockt erst hinein.
- **Schutz:** der Talisman (Abschnitt 6), der gebannte Ring um den Hexenturm, und (Vorschlag) wer dicht bei einem Träger steht.

## 4. Was sie sieht: die Trugbilder

Drei Stufen nach **Trug**. Alles ist lokal und kosmetisch (kein Netzobjekt, kein Host-Zustand, wird nicht gespeichert), nur der betroffene Spieler sieht es.

### Stufe 1, Flüstern (Trug ab 0,15): der Wald schaut zurück
- Augenpaare im Nebel, die sich schließen, wenn man hinsieht (die `AmbushEyes` gibt es schon, hier hexengrün statt magenta).
- Das Gesicht einer Hexenulme folgt ihr mit den Augen oder öffnet den Mund, wenn sie vorbei ist.
- Flüstern von der Seite, Schritte hinter ihr, die aufhören, wenn sie stehen bleibt.
- Ein Schatten in Menschenform zwischen zwei Stämmen, einen Augenblick lang.

### Stufe 2, Trug (ab 0,45): Dinge, die nicht stimmen
- **Falsche Funde:** ein Item liegt da und glitzert, beim Aufheben zerfällt es zu grünem Rauch.
- **Falsche Freunde:** Valdric oder Gustav stehen stumm im Nebel und sind beim Näherkommen ein Baumstumpf.
- **Das HUD lügt mit:** die Entfernung an der Questranke zittert, der Lebensbalken zuckt kurz, als wäre sie getroffen. Nur Zucken, die echten Werte kehren sofort zurück.
- **Die Karte bleibt verschleiert:** solange sie halluziniert ist, deckt `MapDiscovery` im Hexenwald nichts auf. Der Wald lässt sich erst mit klarem Kopf kartieren (starker, billiger Effekt, und ein sichtbarer Lohn für den Talisman).

### Stufe 3, Wahn (ab 0,7): die Angriffe
Das Kernstück. In zufälligen Abständen (40-110 s, bei vollem Trug und nachts dichter, nie zwei zugleich) entsteht ein **Trugwesen**:

1. Es bricht wie ein echtes aus dem Boden oder kommt aus dem Nebel gelaufen, pirscht, umkreist.
2. Es holt aus, die rote Warnzone liegt auf dem Boden, genau wie beim echten.
3. **Im Schlag zerfällt es:** die Glieder lösen sich von außen nach innen in Rauchfäden auf, die im Nebel verwehen; ein dumpfer Sog statt des Treffergeräuschs, die Kamera zuckt, kein Schaden. Wer vorher zuschlägt, schlägt durch Rauch: die Klinge trifft nichts, das Wesen verpufft an der Schnittlinie.

Erst nur die **Schattenspinne**, später Lauscher (sein Schuss verpufft kurz vor ihr) und Brecher (rammt durch sie hindurch) als weitere Trugwesen.

**Zeichen, an denen man Trug erkennt** (lernbar, belohnt Hinsehen, nie ganz sicher):
- keine Schattenspur am Boden (echte hinterlassen `ShadowPatch`-Abdrücke),
- die Augen flackern für einen Frame hexengrün statt magenta,
- Tiere fliehen nicht, Krähen bleiben sitzen,
- der Ton stimmt nicht ganz: Schritte leicht versetzt, kein Echo,
- es bemerkt sie auch im Schleichen sofort.

**Warum man sie nicht einfach ignoriert:** im Hexenwald herrscht Dauerdämmer, darum halten sich dort auch am Tag vereinzelt **echte** Schattenwesen (selten, die normale Nachtlogik bleibt). Eines von fünf, sechs Wesen ist echt. Wer jede Spinne für Rauch hält, wird gebissen; wer jede für echt hält, verbraucht sich. Das ist das Spiel des Waldes.

**Fairness:** keine Trugbilder in Dialogen, Zwischenszenen, beim Angeln, im Baumodus, in Räumen; keins, während ein echtes Wesen sie gerade angreift (das Echte soll lesbar bleiben); Pause nach einem Tod.

### Technik der Trugwesen (kurz)
Ein eigener kleiner lokaler Knoten `Phantom` (kein Gegner, keine Trefferbox, kein Host): er leiht sich das Aussehen der Spinne (`SpiderRig` als reine Zeichnung) und spielt ein festes Drehbuch (auftauchen, pirschen, ausholen, zerfallen). Kein echter `ShadowSpider`, damit Nachtregie, Beute, Navigation und Netz unberührt bleiben. Ob der Rig sich ohne die Gegner-KI sauber führen lässt, ist der erste technische Prüfpunkt.

## 5. Mehrspieler

- Der Effekt gilt **pro Spieler** (jeder hat sein `StatusEffects`).
- Jeder sieht **seine eigenen** Trugbilder. Der Mitspieler sieht nur, wie man ins Leere schlägt: das ist gewollt und witzig.
- Wer den Talisman trägt, sieht klar und kann den anderen sagen, was echt ist. Vorschlag: im Lichtkreis des Trägers (rund 9 Tiles) sind auch die anderen geschützt, damit eine Gruppe mit einem Talisman zusammenbleibt.

## 6. Der Talisman der Hexe

Arbeitsname **KLARSICHT** (Alternativen: Nebelauge, Bannknoten, Hexenknoten).

- **Aussehen:** ein Knoten aus Hexendorn und Geisterwedel um einen Splitter Fluchsilber, in der Mitte ein hexengrünes Auge, das nachts glimmt. Dieselbe Machart wie die Talismane, die schon in den Hexenulmen hängen: die stammen von ihr, der Wald hängt voller ihrer Bannzeichen.
- **Gattung:** Ohrringe wären falsch (Paar), Armband ist ANGRIFF. Vorschlag **Kette** (KÖRPER), oder bewusst die Gattung, die am wenigsten wehtut, siehe offene Fragen.
- **Wirkung (neuer Perk `clear_sight`):** immun gegen HALLUZINIERT; der Nebel weicht in einem weiten Kreis um sie zurück (dieselbe Lichtung, die der Nebelshader schon hat, nur groß); die Karte deckt im Hexenwald wieder auf; echte Wesen im Wald bleiben echt. Dazu ein kleiner Wert, damit er auch draußen nicht nutzlos ist (z. B. +10 Leben).
- **Der Moment:** beim Anlegen zieht sich der Nebel in einer Welle von ihr weg, die Augen im Dunkel gehen aus, das Trugwesen, das gerade vor ihr steht, zerfällt. Zum ersten Mal sieht man den Wald, wie er ist.
- **Nicht dauerhaft geschenkt:** wer ihn ablegt (etwa für die Rissfeder), halluziniert im Wald wieder. Das macht ihn zu einer echten Wahl statt zu einem Schlüssel, den man einmal dreht.
- **Einführung der Talismane:** heute öffnet der erste Talisman-Platz mit Stufe 5. Wer vorher zur Hexe kommt, könnte ihn nicht tragen. Vorschlag: die Hexe **öffnet den ersten Platz selbst** (Questflagge zählt wie die Stufe-5-Belohnung), die Stufen 15 und 25 bleiben.

## 7. Die Storyquest (Gerüst, Texte kommen vom Dialogautor)

Arbeitstitel **"WAS IM NEBEL WOHNT"**. Start nach Gustavs Rettung (die Stadt steht, die Werkzeuge sind da).

1. **Das Gerücht.** Gustav hat auf seiner Fahrt Lichter im Süden gesehen und Holz, "das einen ansieht". Valdric weiß mehr, als er sagt, und rät ab. Ziel: die Südküste.
2. **Der Rand.** Ein alter Wegweiser an der Küstenwiese, das Brett zum Wald ist abgeschlagen. Der Boden wird dunkel, der erste Nebel. HALLUZINIERT erscheint, die Tutorialkarte.
3. **Die erste Lüge** (gesetzt, nicht zufällig): eine Spinne bricht direkt vor ihr aus dem Boden, holt aus, zerfällt. Ellie: Schweigen, dann ein Satz. Ab hier laufen die zufälligen Trugbilder.
4. **Der Weg hinein.** Sie folgt den Talismanen in den Bäumen: wo welche hängen, ist der Nebel dünner (lesbarer Pfad ohne Questmarker-Linie). Unterwegs das erste **echte** Wesen, damit die Regel sitzt.
5. **Die schlimmste Lüge** (gesetzt): der Kreuzweg wiederholt sich. Drei Augenpaare, drei Spinnen, dieselbe Kamera wie beim Überfall, aber diesmal kommt kein Ritter. Sie zerfallen alle drei im selben Augenblick. Der Wald benutzt ihre eigene Erinnerung.
6. **Der Turm.** Ein Ring ohne Nebel, der Turm darin. HALLUZINIERT erlischt am Ring. Die Hexe (Figur später).
7. **Der Preis.** Die Hexe gibt nichts umsonst: sie bindet den Talisman aus dem, was im Wald wächst. Ellie sammelt **Fluchsilber, Hexendorn und eine Alraune**, im Nebel, halluzinierend. Das gibt der gebauten Pflanzenwelt ihren ersten Zweck.
8. **Klarsicht.** Sie bekommt den Talisman, der erste Platz öffnet sich, Tutorialkarte zum Anlegen, der Nebel weicht. Folgequest offen (die Hexe will dafür etwas).

## 8. Der Hexenturm (nur Richtung, Ausarbeitung danach)

Ein Festungsturm, den der Wald sich geholt hat: gemauert aus dem dunklen Stein der Fluchsilber-Felsen, von einer riesigen Hexenulme umwachsen, deren Äste ihn halten und deren Gesicht über dem Tor sitzt; schiefe Erker, ein Hexenhut als Dach, grünes Licht in den Fenstern, Talismane an jedem Ast, Krähen. Eigener Innenraum über `Interiors`. Um ihn der gebannte Ring.

## 9. Bau in Schritten

| # | Schritt | Ergebnis |
|---|---|---|
| 1 | Nebel im Hexenwald (Shader-Wiederverwendung, Tönung, Dauerdämmer) | sichtbar, ohne Regeln |
| 2 | Effekt `hallucinated`: Host-Auffrischung, HUD-Schild, Trug-Wert, Stufe 1 (Augen, Flüstern, Baumgesichter) | spielbar, harmlos |
| 3 | Trugwesen Spinne mit Zerfall, Erkennungszeichen, Töne; echte Wesen am Tag im Wald | das Kernstück |
| 4 | Stufe 2 (falsche Funde, falsche Freunde, HUD-Zucken, verschleierte Karte) | Tiefe |
| 5 | Talisman KLARSICHT: Item, Icon, Perk, Nebellichtung, Anlege-Moment, Entwicklerknopf | Lösung |
| 6 | Turm (Art, Innenraum, Ring) | eigener Arbeitsgang |
| 7 | Storyquest, Hexe, Dialoge | braucht 5 und 6 |

Schritte 1-5 brauchen weder Turm noch Hexe und lassen sich über das Entwicklermenü prüfen.

## 10. Offene Entscheidungen

1. ~~Schaden~~ **Entschieden 2026-11-10: Trugwesen machen keinen Schaden und kosten nichts.**
2. **Echte Wesen am Tag im Wald:** ja (Vorschlag, sonst ignoriert man alles) oder nein?
3. **Gattung des Talismans** und ob er dauerhaft getragen werden muss, oder ob die Hexe den Schutz später fest macht.
4. **Erster Talisman-Platz** durch die Quest statt Stufe 5?
5. **Sammelauftrag der Hexe** (Schritt 7 der Quest) ja/nein, und welche Mengen.
6. **Gruppenschutz** im Kreis des Trägers?
7. **Name** des Effekts auf dem Schild (HALLUZINIERT) und des Talismans.
8. **Wie weit das HUD lügen darf** (Zucken des Lebensbalkens kann manche Spieler ärgern).

## 11. Entscheidungen und Stand (2026-11-10)

Entschieden: (2) bei Tag keine echten Kreaturen im Hexenwald; (3) der Talisman sind Ohrringe, müssen getragen werden, schwache Werte, Seltenheit selten; (4) die Quest schaltet Talismanplatz 1 frei (Stufe 5 ebenfalls), die Quest selbst gibt es erst ab Stufe 5; (6) kein Gruppenschutz, jeder braucht eigene, alles lokal; (7) Name "Ohrringe der Klarheit"; (8) HUD-Lügen: Lebens- oder Ausdauerranke zeigt kurz einen falschen, niedrigen Wert. Trugwesen lösen sich nur auf (Ausblenden, kein Partikelrauch). Offen: (5) Sammelaufgabe für die Hexe.

Gebaut: Nebel (`night_fog.gdshader` `hex`/`clear_px`, `NightAtmosphere`), Effekt `hallucinated` (`StatusEffects._breathe_mist`, `data/status_effects.json`), `Hallucinations` + `PhantomSpider` (src/fx), HUD-Lüge (`SapVine.lie`), Karte deckt im Wahn nicht auf, `clarity_earrings` mit Perk `clear_sight`, Hinweiskarte, Dev-Knöpfe OHRRINGE DER KLARHEIT / IN DEN HEXENWALD. Test `tools/test_hexenwald_mist.tscn` (22 Prüfungen), Aufnahmen `tools/preview_hexenwald_mist.tscn -- --dir=/abs [--night]`.
Nicht gebaut: die Quest (samt Platz-1-Freischaltung und Stufe-5-Sperre), Baumgesichter, die Hexe.

**Hexenturm (Entwurf, nicht in der Welt):** `python3 tools/art_witch_tower.py [preview.png]` -> `assets/props/witch_tower/` (Turm, Glühen, Boden, wiegende Teile Krone/Anhänger/Laternen, Streifen Fenster/Auge/Kessel, `witch_tower.json`), Node `WitchTower` (src/entities/props/witch_tower.gd), Ansicht `tools/preview_witch_tower.tscn -- --dir=/abs [--at=x,y]`.
