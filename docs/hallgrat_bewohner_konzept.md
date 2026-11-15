# Hallgrat: Bewohner (Konzept, 2026-11-14)

Ergänzt `docs/stadt_westen_konzept.md` §6 (Figurenliste) und §8 (Ideen). Namen und alle Texte sind Platzhalter für den Dialogschreiber (`docs/prompts/dialogue_writer.md`).

## 0. Entscheidungen (Fragerunde 2026-11-14)

| # | Frage | Entscheidung |
|---|---|---|
| 1 | Umfang | **Kernbesetzung** von sechs Figuren, richtig ausgebaut; die übrigen aus §6 folgen später |
| 2 | Statisten | **Ja**, 20–30 namenlose Stadtleute aus einem Baukasten |
| 3 | Art | **Hauptagent**, Ellipsoid-Renderer, Siedler-Rig-Format (wie Gustav, Torben, Jorun) |
| 4 | Alltag | **Voll reaktiv**: Tagespläne, Begegnungen untereinander, Reaktionen auf Ellie und auf das Wetter |
| 5 | Häuser | **Verschwinden an der Tür**; keine Innenräume in diesem Schritt |
| 6 | Ansprechen | **Wie Gustav**: Plauderzeile, tägliches Vertrauen, je nach Figur Laden/Handwerk und Aushänge |
| 7 | Stadtstufen | **Nicht jetzt**; die Stadt ist von Anfang an belebt |
| 8 | Nacht | Pims **Lichtrunde**, **Wachen** auf der Mauer, **Gasthausabend**; alle anderen gehen hinein |
| 9 | Ankunft | **Brann am Osttor** hält Ellie auf; ohne das Gespräch bleibt das Tor zu |
| 10 | Kinder/Katze | **Beides jetzt**: drei Kinder und die Katze Schiefer |

## 1. Ziel

Hallgrat soll sich anfühlen wie ein Ort, an dem man zu Besuch ist, nicht wie die eigene Stadt:
- Die Menschen gehören sich selbst. Sie haben Gewohnheiten, Wege, Freunde und Launen.
- Sie bemerken die Fremde. Erst schauen sie nach, nach ein paar Tagen grüßen sie.
- Der Tag hat einen hörbaren Takt: Läden gehen auf, der Markt läuft, die Glocke schlägt (`Hallgrat.DUSK_BELL` 0.79), Pim zündet die Laternen an, das Gasthaus singt, dann ist es still.

## 2. Kernbesetzung (6)

Alle Figuren sind `HallgratResident` (siehe §9). „Heim“ ist eine Gebäude-id aus `data/hallgrat.json` `placed`.

| Figur | Rolle | Heim / Arbeitsort | Tag | Laden / Handwerk | Besonderes |
|---|---|---|---|---|---|
| **Brann** | Torwächterin, alte Soldatin | `torhaus` / Osttor | steht am Tor, Mittag am Brunnenhof, abends auf dem Wehrgang | keiner; gibt Aushänge (Wache, Botengänge) | Torprüfung (§7); kennt jeden Gast beim Namen |
| **Ilvane** | Hüterin der Wächterin | `hueterhalle` / Forum | kehrt den Ring, zündet Kerzen, sitzt still vor der Statue | Tausch: Kerzen, Weihrauch, Wegstein-Splitter | spricht in Rätseln, weiß, wenn Ellie Statuen erweckt hat (`Waystones`) |
| **Odrik „Meißelbart“** | Steinmetzmeister | Haus an den Staffeln / `steinmetzhof` | meißelt am Quader (Clip mit Schlag + Splittern), Mittag im Gasthaus | Handwerk: Steinbau-Rezepte für Glimmrast (später, `unlocks`) | arbeitet an der Statue (§8.7 im Stadtkonzept, später) |
| **Tamsa** | Glasschleiferin | `staffeln_2_0` (laden) / `glasschleiferei` | schleift am Rad (Funken, Ozon), läuft zum Markt, neckt die Kinder | Laden: Kristall, Glas, Talisman-Steine (SCHLIFF wie bei Ilva) | flink, rennt gern; Leitstein-Questkette später |
| **Pim** | Lichtknecht, 14 | Kammer im `lagerhaus` | tagsüber Botengänge, Laternen putzen | keiner; Aushänge (Laternenöl, Dochte) | **Lichtrunde** zur Dämmerung (§5); Ellie kann mitgehen (Szene später) |
| **Hedda** | Wirtin | `gasthaus` | fegt vor der Tür, kauft am Markt, Tische draußen, abends Ausschank | Laden: Essen, Getränke; Rezepte für das Kochbuch später | Gerüchte-Zeilen; Gasthausabend (§5) |

Die übrigen Figuren aus §6 (Sebald, Perrin, Corvin, Vogt Maeve, Jorun als Hallgrat-Gast) kommen in einem späteren Schritt dazu.

## 3. Statisten-Baukasten

Ziel sind 24 Stadtleute (Obergrenze in den Daten), die sich aus wenigen Teilen ergeben und doch verschieden aussehen.

**Aussehen:** ein Rig (Siedler-Format), mehrere Bögen.
- Statur: schmal, kräftig, alt (gebückt).
- Kleidung: drei Schnitte (Kittel, Rock mit Schürze, Mantel), je fünf Farbpaletten aus dem Stadtwappen und erdigen Tönen.
- Kopf: Haare (kurz, Zopf, Kapuze, Hut, Glatze), Haarfarben.
- Tragegut: nichts, Korb, Sack, Krug, Brett, Werkzeug.

Die Kombination ist eine reine Funktion von Welt-Saat und Statisten-Nummer, also auf jedem Rechner gleich. Gerendert werden etwa acht Grundkörper in acht Richtungen. Kleidung, Kopf und Tragegut sind eigene Ebenen-Bögen, die der Knoten übereinanderlegt (wie die Talisman-Ebene bei Ellie). So entstehen viele Varianten, ohne dass die Bögen explodieren.

**Rollen statt Namen.** Jeder Statist bekommt eine Rolle mit eigenem Tagesplan:
- Händler: am Stand, Ware auslegen und rufen
- Träger: Ware zwischen Lagerhaus, Karrenhof und Markt
- Steinsetzer: am Gerüst, an der Mauer
- Marktgänger: einkaufen und schauen
- Alte: auf der Bank, am Brunnen
- Wäscherin: Wäscheleine, Brunnen
- Wache: Tor, Wehrgang, nachts mit Laterne

**Ansprechen:** E gibt eine Zeile aus dem Pool der Rolle, des Ortes und der Tageszeit. Statisten haben kein Vertrauen und keinen Laden.

## 4. Kinder und Schiefer

**Die Kinder Moos, Fink und Lia** gehen gemeinsam als kleine Gruppe:
- Fangen am Brunnen, Murmeln auf den Staffeln, Verstecken hinter Fässern.
- Sie laufen der Karawane nach und rennen weg, wenn Ellie zu schnell kommt.
- Abends holt sie eine Stimme ins Haus.
- Kleinere Figur (Skala ca. 0.7), eigener Bogen mit den Clips idle, run, crouch (verstecken), throw (Murmel), wave.

Ihre Funde (Kieselglas, Federn) sind ein späterer Schritt.

**Die Katze Schiefer:**
- Schläft auf der warmen Esse (Steinmetzhof oder Glasschleiferei), putzt sich, wechselt in die Sonne.
- Folgt Ellie ein Stück, wenn sie Fisch im gewählten Slot hat.
- E = STREICHELN: Ellie hockt sich hin (Fütter-Clip von Ellie, Bogen 14, wiederverwendet), die Katze schnurrt (Herzchen-Funken, Ton).
- Kein Schaden, keine Beute, kein Vertrauen. Sie gehört zu den Tieren (Designregel: kein Tier wird verletzt).
- Eigener kleiner Bogen mit `tools/art_cat.py` (Ellipsoid-Renderer wie die Kaninchen).

## 5. Der Tag der Stadt

Zeiten sind Anteile des Tages (`TimeManager`: 0.5 = Mittag, Nacht ab 0.833, bis 0.167).

| Zeit | Was passiert |
|---|---|
| 0.20–0.29 | Erste Leute draußen: Brann zieht am Tor auf, Hedda fegt, Bäckerduft (Text) |
| 0.29–0.45 | Läden öffnen, Werkstätten arbeiten, Träger laufen, Kinder kommen heraus |
| 0.45–0.60 | Markt am vollsten (Steinmarkt und Ring um die Wächterin), Mittag im Gasthaus und auf Bänken |
| 0.60–0.76 | Arbeit, Botengänge, Kinder spielen, Alte am Brunnen |
| 0.76–0.79 | Läden schließen, Stände werden abgedeckt |
| 0.79 | **Glocke** (gibt es schon) |
| 0.79–0.86 | **Lichtrunde**: Pim geht eine feste Route über alle Laternen (`deko_laterne` und Laternen der Wände) und zündet sie an; Laternen sind bis dahin dunkel |
| 0.82–0.95 | **Gasthausabend**: 6–10 Leute vor und im Gasthaus, Gesang (Ton), Licht |
| 0.86–0.20 | Alle anderen drinnen; **Wachen** mit Laterne auf dem Wehrgang der Stadtmauer und an den Toren; Ilvane am Forum |

Bei der Nachtstufe „Druck“ oder einem Vorstoß in Hallgrat (später) gelten die Angstregeln der Siedler (`fear_on`): rennen, verstecken, Wachen halten.

## 6. Reaktionen

Alle Reaktionen sind kosmetisch und laufen auf jedem Rechner selbst: Blick, Gruß, Ausweichen, Sprechblase. Sie verschieben **nie** den Platz, den der Plan vorgibt (siehe §9).

**Auf Ellie** (die nächste lokale Spielerin oder ein Mitspieler):
- **Ansehen:** Wer sie in 60 px sieht, dreht den Kopf beziehungsweise den Körper zu ihr und schaut nach, wenn sie vorbeigeht.
- **Grüßen:** Nicken oder Winken, abhängig von der Bekanntschaft. Fremd = Blick und Getuschel; bekannt (Torprüfung vorbei) = Nicken; Vertrauen = Winken und Name.
- **Ausweichen:** Läuft sie auf einen Gehenden zu, macht er einen Bogen. Das ist nur ein seitlicher Versatz der Figur, der Plan bleibt gleich.
- **Sprint und Waffe:** Rennt sie durch die Stadt oder schwingt eine Waffe, schrecken Leute zusammen, Kinder laufen weg, Brann ruft.
- **Verletzt:** Wer sie mit wenig Leben sieht, sagt etwas dazu (Pool `hurt`).
- **Fortschritt:** Zeilen-Pools zu Ellies Taten (Wegstein erweckt, Boss gefallen, …), wie das Reaktionssystem in §8.16 des Stadtkonzepts.

**Untereinander:**
- **Plauderpaare:** Treffen sich zwei Figuren auf ihrem Weg, bleiben sie manchmal kurz stehen, drehen sich zueinander und zeigen Sprechblasen (Gesten-Clip). Das ist im Plan vorgesehen, siehe §9.
- **Feste Treffpunkte:** Brunnen, Bänke, Stände. Dort entstehen Grüppchen aus Figuren, deren Pläne zur selben Zeit dort enden.

**Wetter:**
- Bei Regen gehen Leute unter Vordächer, unter den Stall-Anbau oder unter Marktplanen, oder sie laufen schneller und mit Kapuze.
- Bei Sturm gehen alle hinein.
- Das Wetter ist schon eine reine Funktion von Saat und Zeit (`WeatherRules`), also bleibt auch das Unterstellen auf jedem Rechner gleich.

## 7. Ankunft: Brann am Osttor

- Am Osttor steht vor der ersten Ankunft eine **Torsperre** (Gitter oder Schranke im Torhaus). Sie ist zu, solange die Spielerin das Flag `hallgrat_admitted` (Quest-Flag, pro Spielerin) nicht hat.
- Kommt Ellie nahe, tritt Brann vor (Sprechbox: „Halt. Wer kommt da den Westweg herauf?“) und es folgt ein **Dialog**. Das Rätsel statt einer Waffe aus §6 des Stadtkonzepts ist eine Platzhalterfrage mit drei Antworten; jede führt zum Ziel, die Antwort färbt nur Branns Meinung. Danach setzt sie das Flag, die Sperre öffnet sich und Brann sagt einen Satz zur Stadt.
- **Mehrspieler:** Die Sperre ist für alle sichtbar. Eine Spielerin ohne Flag bekommt bei sich eine Kollision, wer das Flag hat, geht durch. Das ist eine lokale Kollisionsausnahme wie bei `RiverDepth`. Bewegung ist lokal, darum genügt das.
- Danach kennen die Bewohner sie (`known`, siehe §6). Auf der Karte erscheint der Name HALLGRAT.

## 8. Ansprechen, Vertrauen, Läden, Aushänge

- Für die sechs Kernfiguren gilt dasselbe Muster wie bei Gustav: E = ANSPRECHEN. Einmal am Tag gibt das Vertrauen (+10). Dazu eine Zeile aus `chat`-Pools (Quest-Stand, Ort, Nacht, irgendwas) und die `talk`-Stufen nach Vertrauen.
- Wer einen Laden hat, bekommt danach HANDELN (`ShopWindow`, Einträge in `data/shops.json`).
- Handel und Vertrauen laufen über `TownManager.register_person/person_node/register_outpost`. So läuft es schon für Esma und Ilva: Hallgrat-Figuren sind wie diese **`away`-Figuren**, Glimmrast kennt sie, aber sie wohnen nicht dort.
- **Aushänge:** Kernfiguren, die Ellie getroffen hat (`TownManager.has_met`), dürfen Aushänge an Glimmrasts Questtafel hängen (fetch/kill aus `board.json`). Eine eigene Tafel in Hallgrat kommt später.
- **Geschenke:** `likes` wie bei Gustav (Odrik mag Fluchsilber und Mondstein, Tamsa Kristalle, Hedda Beeren und Pilze, Pim Harz und Glimmkappen, Ilvane Kerzenzutaten, Brann Fisch).

## 9. Technik

**Grundsatz wie bei den Siedlern: Wo jemand ist, ist eine reine Funktion der Uhr.**
- Plan, Heim, Wege und Saat bestimmen den Ort. Darum gibt es kein Netzwerkobjekt pro Figur, nichts wird gespeichert, und Mitspieler sehen dasselbe.
- Nur Vertrauen, Bekanntschaft und Käufe gehen über den Host (wie bisher bei Siedlern).

**Neue Teile:**

| Teil | Aufgabe |
|---|---|
| `data/hallgrat_people.json` | Kernfiguren (Spots, Pläne, Clips, Pools, Laden, likes), Statisten-Rollen, Baukasten-Teile, Kinder, Katze, Lichtrunde, Gasthausabend, Begegnungsorte |
| `HallgratPeople` (Knoten von `Hallgrat`, src/world/) | erzeugt die Figuren nur, solange eine lokale Spielerin in der Stadt oder in ihrer Nähe ist (Begrenzung wie bei Hallgrat-Gebäuden), gibt sie wieder frei, verteilt Statisten-Rollen aus der Saat, plant Begegnungen |
| `HallgratWays` (pur) | Wegenetz aus `ways`, `door_paths`, Plätzen und Treppen der Stadt; kürzeste Wege zwischen Spots. Ebenen-Wechsel nur über Treppen und Rampen (Relief-Verbinder), A* wie `TownWays`, Ergebnis gecacht |
| `HallgratResident` (src/entities/npcs/) | Darstellung und Interaktion; die Logik teilt es mit `Settler`, wo es geht (Clip-Wahl, Sprechblase, Talk, Vertrauen). Es ist **kein** `Settler`, weil es nicht an `TownManager` hängt |
| `HallgratExtra` | Statist: dieselbe Basis, Ebenen-Bögen, Rollenplan, Pool-Zeilen |
| `HallgratKid`, `HallgratCat` | kleine Sonderfälle (Gruppenbewegung, Streicheln) |
| `TownGate` | Branns Torsperre (§7) |

**Begegnungen deterministisch:**
- Plauderpausen werden beim Planen aus der Saat und dem Tag gewürfelt: „Figur A und B treffen sich um 0.41 am Brunnenhof für 0.01“. Beide Pläne bekommen dieselbe Pause.
- Darum sieht jeder Rechner dieselbe Szene, ohne Netzwerk.

**Reaktionen auf Ellie:**
- Rein lokal (Kopf drehen, Gruß-Clip, Sprechblase, seitlicher Versatz bis 8 px).
- Verändern nie die geplante Position. Für Mitspieler sieht eine Figur also leicht anders aus, steht aber am selben Ort.

**Laternen der Lichtrunde:**
- Brennen nachts erst, wenn Pims Plan an ihnen vorbei ist. Das ist eine reine Funktion der Uhr und der Routen-Reihenfolge.
- Die Laternen (`HallgratBuilding` mit `light`) fragen `HallgratPeople.lamp_lit(id, time)`.

**Leistung:**
- Höchstens etwa 40 Figuren geladen, nur in der Nähe.
- Routen werden einmal pro Tag und Figur gebaut (Jobs-System erlaubt, reine Funktion).
- Ein Bogen pro Figurart, Ebenen für Statisten.

## 10. Art

- Kernfiguren je ein eigener Bogen über den Ellipsoid-Renderer (`tools/art_hallgrat_people.py`): Siedler-Rig-Format, 8 Richtungen, Feet-Anker, Glow-Bogen nur wo nötig (Tamsas Funken, Pims Laterne, Ilvanes Kerze).
- Clips:
  - alle: idle, walk, talk (Geste), wave, nod, look (Kopf)
  - je Rolle eigene: Brann `guard` und `halt`, Ilvane `sweep`, `candle` und `kneel`, Odrik `chisel` (strike), Tamsa `grind` (Funken) und `run`, Pim `light` (Stange hoch) und `polish`, Hedda `sweep` und `serve`
- Statisten: Grundkörper und Ebenen (§3), Clips idle, walk, talk, wave, carry, sit, work (allgemein).
- Kinder und Katze wie in §4.
- Portraits für die Kernfiguren erst, wenn die Dialoge geschrieben werden (`docs/dialogue_art.md`). Bis dahin zeigt die Dialogbox die Silhouette.
- Klang: `tools/audio_hallgrat_people.py` (Meißel, Schleifrad, Fegen, Gesang, Schnurren, Murmeln, Rufe), Platzhalter.

## 11. Bau-Reihenfolge

1. **Wegenetz und Plan:** `HallgratWays`, `hallgrat_people.json`, `HallgratPeople` mit Platzhalterfiguren. Test: Routen, Treppen, Plan als Funktion der Uhr, gleiche Positionen auf zwei „Rechnern“.
2. **Kernfiguren-Art und Interaktion:** sechs Bögen, ANSPRECHEN, Vertrauen, Läden (Tamsa, Hedda, Ilvane), `register_person`.
3. **Statisten-Baukasten:** Ebenen-Bögen, Rollenpläne, Pool-Zeilen.
4. **Leben:** Begegnungen, Reaktionen auf Ellie, Wetter, Lichtrunde mit den Laternen, Gasthausabend, Wachen.
5. **Kinder und Schiefer.**
6. **Ankunft:** Brann und die Torsperre, Mehrspieler-Ausnahme, Bekanntschaft.

Jeder Schritt hat einen eigenen Test (`tools/test_hallgrat_people.tscn`) und Bilder (`tools/preview_hallgrat_people.tscn -- --dir=/abs --times=..`).

## 12. Offen (später zu entscheiden)

- Branns Frage am Tor (Inhalt, schreibt der Dialogschreiber).
- Hedda: Hausmannskost als echte Heil-Gerichte oder nur Kochbuch-Rezepte?
- Eine eigene Aushangtafel in Hallgrat oder nur Glimmrasts Tafel?
- Pims Lichtrunde als begleitbare Szene (Ellie trägt die Stange) – nach Schritt 4.
- Die übrigen Figuren aus §6 und der Umzug einer Figur nach Glimmrast (§11 Frage 8 des Stadtkonzepts).

## 13. Stand

### Schritt 1 gebaut (2026-11-14): Wegenetz und Tagespläne

**`HallgratWays`** (src/world/hallgrat_ways.gd, pur, `RefCounted`) ist das Wegenetz der Stadt:
- Ein Raster aus 8-px-Zellen über die `bounds` der Stadt.
- Gesperrt ist, was auch Ellie aufhält:
  - Relief-Kollision und Wandflächen
  - die Grundrisse aller Häuser, Deko-Dinge und Mauerstücke, mit denselben Formen wie die StaticBodies von `HallgratBuilding` (Kasten, `poly`, `chain` + `thick`, Turmkreise), jeweils um 4 px vergrößert
  - die Stämme der Stadtbäume aus `greenery`
- Pflaster (`hallgrat_clear`) und Türwege kosten 1.0, Gras 1.7. Jede feste Nachbarzelle kostet 0.6 extra, damit die Leute in der Mitte der Straße gehen.
- `route(a, b)` sucht mit A* (8 Richtungen, keine Ecken schneiden) und zieht den Weg gerade, wo die Linie frei bleibt und nicht ins teurere Gras abkürzt. Danach werden die Punkte alle 4 px neu verteilt.
- Wege werden im Cache gehalten, mit Mutex. Ebenen wechseln die Leute nur über Rampen, Treppen und Felsstufen, weil das Relief nur dort offen ist.

**`HallgratPeople`** (src/world/hallgrat_people.gd, Kind von `Hallgrat`):
- Baut Netz, Spots und alle Wege der Pläne einmal auf einem `Jobs`-Worker, sobald eine lokale Spielerin innerhalb von `bounds` + 40 Kacheln ist. Das dauert etwa 1 s.
- Erzeugt die Figuren nur in dieser Nähe und gibt sie beim Gehen wieder frei.
- `state_at(id, t)` ist eine reine Funktion der Uhrzeit:
  - Es gilt der Eintrag, der zuletzt vor `t` begonnen hat (Lücken zwischen Einträgen halten den letzten Spot).
  - Zu seinem Beginn läuft die Figur vom vorigen Spot los, mit `walk_speed` 30 px/s. Ist der Weg zu lang für den Eintrag, läuft sie schneller, sodass sie nach 80 % der Zeit da ist.
  - Bei Spots mit `inside` ist sie weg, sobald sie dort ankommt.
- `spot_raw` versteht `px`, `door` (Gebäude-Tür + 6 px), `building` + `at` (px von den Füßen) und `place` + `at` (Kacheln vom Platzmittelpunkt). `HallgratWays.snap` legt jeden Spot auf die nächste freie Zelle.

**`HallgratResident`** (src/entities/npcs/hallgrat_resident.gd) ist vorerst nur ein Platzhalter: eine gezeichnete Figur in den Farben aus `look` (`coat`, `under`, `skin`, `hair`, `tall`), mit Schritt-Wippen und Blick nach links oder rechts.

**Daten:** `data/hallgrat_people.json` mit den sechs Kernfiguren (Spots und Pläne wie in §2 und §5).

**Nebenbefund:** Der Brunnenhof war rundum zugemauert. Er liegt auf einem Zipfel von Ebene 3, dessen Hals unter einem Haus verläuft, und die Ringmauer um den Brunnen schloss den Rest. `place_hallgrat_deco.py` lässt jetzt:
- kleine Plätze (Art `square`, unter 10 × 10 Kacheln) ganz ohne Mauer,
- zwischen zwei Mauerstücken immer eine Lücke von 24–36 px.

**Test:** `tools/test_hallgrat_people.tscn` (`HALLGRAT PEOPLE OK`, 233 Checks). Er prüft:
- das Netz ist bei jedem Bau gleich,
- 93 % des freien Bodens hängen zusammen, und jeder Platz, Hof und Garten ist vom Osttor aus erreichbar,
- jeder Spot liegt auf dem Netz, jeder Weg existiert, bleibt auf freien Zellen, hat keine Lücken und klettert nur über Verbinder,
- keine Sprünge (gemessen Sekunde für Sekunde über den ganzen Tag), nachts alle drinnen, mittags alle draußen,
- im echten Weltlevel erscheinen die Figuren in der Stadt am geplanten Ort und gehen wieder, wenn die Spielerin die Stadt verlässt.

Mit `-- --dir=/abs` macht er Bilder vom Forum und vom Steinmarkt.

## 14. Stand / Schritt 2 gebaut (2026-11-15)

**Art.** `py -3 tools/art_hallgrat_people.py [contact.png]` rendert alle sechs Figuren in rund 50 s:
- Schnellblick: `quick out.png [ids]`, einzelne Figuren mit `only brann,pim`.
- Gemacht vom Hauptagenten mit dem Ellipsoid-Renderer der Heldin, im Settler-Format: 76×96, Füße (38, 80), 8 Reihen O SO S SW W NW N NO.
- Ausgabe: `assets/characters/hallgrat_<id>.png`, `_glow.png` (nur Flammen und Funken, unlit) und `data/hallgrat_<id>_rig.json`.
- Allgemeine Clips: idle 4, walk 6, talk 4, wave 6.
- Eigene Clips:

| Figur | Clips | Aussehen |
|---|---|---|
| Brann | guard, halt | Speer, Kettenhemd über schieferblauem Wams, weinroter Halbmantel, Horn |
| Ilvane | sweep, kneel, candle | bodenlange Robe, silberweißes langes Haar, Stola in Teal |
| Odrik | chisel (`strike` 3) | Bart in zwei Zöpfen, Lederkappe, staubige Schürze |
| Tamsa | grind, run | Kupferdutt mit Bleistift, Schutzbrille auf der Stirn |
| Pim | polish, light, run | kleiner, Senfjacke, Schirmmütze, Ruß auf der Wange |
| Hedda | sweep, serve | Kopftuch, weinrotes Kleid, Schürze, Tablett mit zwei Krügen |

**Figur.** `HallgratResident` ist jetzt ein `Interactable`:
- Der Clip kommt aus dem Planzustand: `walk` beim Gehen, sonst der Clip des Spots. Es gibt 8 echte Richtungen.
- Wer angesprochen wird, dreht sich 5 s zur Spielerin.
- E wie bei Gustav und Esma:
  - ANSPRECHEN: das erste Gespräch des Tages bringt +10 Vertrauen (`TownManager.request_talk`) und eine `chat`-Zeile in der Sprechblase.
  - Danach HANDELN, wenn die Figur einen Laden hat.
  - AUFTRAG ABGEBEN bei fertigen Aushängen.
- Die Stadt kennt jede Figur über `register_person`. Der Laden gilt über `register_outpost(role, Position)` dort, wo die Figur gerade steht.
- Der Host hält die Figuren, solange IRGENDEIN Spieler in der Stadt ist, weil Handel und Abgaben auf dem Host geprüft werden. Andere Peers halten sie nur für den eigenen Spieler.

**Daten.**
- `data/settlers.json`: sechs Einträge mit `away: true` und `enabled: false` (keine Stadtfigur, wie Esma), `likes` und `chat` (Pools `spot`/`night`/`any`, Platzhalter für den Dialogautor).
- `data/shops.json`:
  - `tamsa_glass`: Kristalle und Edelsteine der Stufe 1, kauft Rohsteine.
  - `hedda_inn`: Essen, kauft Fisch und Pilze.
  - `ilvane_hall`: Kerzen, Phiolen, Wundblatt, Mondstein, kauft Mondglocke, Nebellilie und Harz.

**Test:** `tools/test_hallgrat_people.tscn` prüft zusätzlich:
- Bogen und Rig passen zusammen, und jeder Clip, den ein Spot verlangt, ist gezeichnet.
- Personeneintrag und Läden samt Waren existieren.
- In der Welt: Tamsa ist der Stadt bekannt, ANSPRECHEN → Vertrauen 10 → HANDELN, der Handel gilt neben ihr, und das Vertrauen steigt nur einmal am Tag.

**Noch nicht gebaut:** Porträts, Reaktionen (Wetter, Nacht, Spielerin), Brann am Osttor, Statisten, Kinder und die Katze.

## 15. Stand / Schritt 3 gebaut (2026-11-15): Statisten-Baukasten

**Abweichung von §3:** statt Ebenen-Bögen (Kleidung, Kopf und Tragegut übereinander) ganze Körper plus Farbtausch. Übereinandergelegte 2D-Ebenen können nicht verdecken (ein Arm vor dem Mantel, ein Korb vor dem Rock), das sah falsch aus. Stattdessen:
- `py -3 tools/art_hallgrat_extras.py [contact.png]` rendert **13 Körper** in rund 2,5 min (Schnellblick `quick out.png [k,k]`).
- Jeder Körper ist eine Kombination aus Statur (schmal, kräftig, alt/gebückt), Schnitt (Kittel, Rock mit Schürze, Mantel), Kopf (kurz, Zopf, Kapuze, Hut, Glatze mit Bart) und Tragegut (Korb, Sack, Krug, Brett, Werkzeug, nichts). Körper 12 ist die Wache mit Helm, Speer und Laterne (Glow-Bogen).
- Ein gemeinsames Rig `data/hallgrat_extra_rig.json` mit den Clips idle, walk, talk, wave, carry (Gehen mit Last), sit (Bank) und work (Hände vorn beschäftigt).
- Kleidung und Haar sind in drei **Schlüsselrampen** gezeichnet, deren Farben sonst nirgends vorkommen. `hallgrat_extra.gdshader` tauscht sie pro Statist gegen eine Palette aus `extras.palettes`: 7 Hauptstoffe, 5 Zweitstoffe, 6 Haarfarben. Ältere tragen fest graues Haar.

**Pläne:** `HallgratExtras` (src/world/hallgrat_extras.gd, rein, Jobs-tauglich) macht aus `data/hallgrat_people.json` `extras` 24 Pläne im Format der Kernfiguren, gesteuert von der festen Saat `extras.seed`:
- Rollen:
  - `wache`: fest 3 Statisten, nachts draußen (Osttor, Torgasse, Forumstufen, Forum), tagsüber im Haus
  - `haendler`: an den Forum-Ständen, hinter der Theke
  - `traeger`: Lagerhaus, Karrenhof, Steinmarkt
  - `steinsetzer`: Steinmetzhof, Quader, Bank
  - `marktgaenger`
  - `alte`: Bank und Brunnen
  - `waescherin`: Wäscheleinen und Brunnen
- Jeder Statist bekommt Körper, Palette, ein bewohntes Haus (verschwindet an dessen Tür) und den Tag seiner Rolle. Die Orte werden aus den Pools gewählt (`home`, `place:<id>`, `door:<id>`, `bench`, `well`, `stall`, `deco:<typ>`, `gate:<id>`), die Zeiten um ±0.012 verschoben.
- `HallgratPeople._build` vergibt jede Spot-Zelle nur einmal (`_free_spot`; die Kernfiguren wählen zuerst), damit niemand in einem anderen steht.

**Figur:** `HallgratExtra` (erbt von `HallgratResident`) geht mit `carry`, wenn der Körper eine Last trägt. E = ANSPRECHEN gibt eine Zeile aus den Pools der Rolle, der Nacht und „any“ (`extras.lines`, Platzhalter). Kein Vertrauen, kein Laden, keine Aushänge.

**Test:** `tools/test_hallgrat_people.tscn` (`HALLGRAT PEOPLE OK`, 1600 Checks) prüft zusätzlich:
- 24 Statisten, auf jedem Rechner dieselben, mindestens sechs Rollen,
- jeder Bogen existiert und jeder Spot-Clip ist gezeichnet,
- mittags sind mindestens 16 draußen und keine zwei näher als 6 px,
- Wachen sind nachts draußen und mittags drinnen,
- in der Welt laufen alle 24 mit eigener Farbe.

Netz und alle 167 Routen bauen in rund 4 s auf einem Worker.

## 16. Stand / Schritt 4 gebaut (2026-11-15): Leben

Alles bleibt eine reine Funktion der Uhr. Wetter, Treffen und Reaktionen sind nur Darstellung auf jedem Rechner: kein Netz, nichts wird gespeichert.

**Pims Lichtrunde:**
- Pim läutet um 0.77 am Turm. Von 0.79 bis 0.92 geht er alle 24 Straßenlaternen (`deko_laterne`) ab, in einer Nächste-Nachbar-Runde mit dem Clip `light` und 2,2 s an jeder Laterne.
- Gebaut wird die Runde von `HallgratPeople._lamp_round` aus `lamp_round` in seinem Plan.
- `HallgratPeople.lamp_times` hält fest, wann jede Laterne angeht, `lamp_lit(at, t)` fragt es ab.
- `HallgratBuilding` zeigt Glut und Licht einer Laterne erst, wenn Pim dort war. Sie brennt bis zum Morgen.

**Abend im Gasthaus:**
- Ein Tageseintrag darf jetzt eine 4. Zahl haben, die Chance, dass ein Statist ihn macht.
- Träger, Steinsetzer und Marktgänger gehen mit 60 % ab 0.80 vor das Gasthaus (Ort `inn`: lockere Runde vor der Tür) und um 0.91 heim.

**Treffpunkte:** stehen zwei Leute keine 30 px auseinander, drehen sie sich zueinander und reden abwechselnd (`_meet`, talk/idle).

**Wetter:**
- Bei Regen gehen stehende Leute zu ihrem nächsten Unterstand: einer Tür oder einem Marktstand, jeweils mit eigener Zelle (`_shelters`, `spot.shelter`). Sie gehen den Weg über das Wegenetz und bleiben dort, bis es aufhört; dann gehen sie zurück.
- Bei Sturm gehen sie hinein.
- Wachen und Arbeitende (`guard`, `work`) bleiben draußen.
- Gesteuert wird das vom Folger in `HallgratPeople._view`, zum Testen über `set_weather(rain, storm)`.

**Reaktionen auf Ellie** (`HallgratResident._react`, lokal):
- Stehende schauen zu ihr, wenn sie näher als 64 px kommt.
- Gruß einmal je 45 s: Bekannte winken und sagen ein Wort, Fremde murmeln manchmal etwas.
- Laufende weichen 8 px seitlich aus.
- Bei einem Sprint dicht vorbei oder einem Schwerthieb in der Nähe schrecken sie zusammen (ein kleiner Hüpfer).
- Ist sie schwer verletzt (unter 30 %), sagen sie etwas, ebenso wenn der Regen einsetzt.
- Die Zeilen stehen in `reactions` (Platzhalter).

**Test** (`HALLGRAT PEOPLE OK`, 1956 Checks) prüft zusätzlich:
- Lichtrunde: Zeiten, Pim steht an der Laterne, wenn sie angeht.
- Abendrunde am Gasthaus.
- Treffen über den Tag.
- Regen: weich zum Unterstand und zurück.
- Sturm: hinein.
- Hedda sieht zu Ellie.

**Nicht gebaut:** Ausschank als eigener Clip im Gasthaus und Wachablösung als Szene.

## 17. Stand / Klang gebaut (2026-11-15)

`py -3 tools/audio_hallgrat_people.py` erzeugt synthetische Platzhalter nach `assets/audio/hallgrat_people/`:
- Meißel `chisel_a..c`
- Schleifrad `grind`
- Besen `sweep_a/b`
- Laterne anzünden `lamp`
- Tuch auf Messing `polish`
- Krug auf Holz `serve`
- Heddas Summen `sing_0..2`
- Rufe der Händler `call_0..2` (Vokale ohne Worte)
- Gemurmel vor dem Gasthaus `murmur` (nahtlose Schleife)

Gesteuert wird alles über `data/hallgrat_people.json` `sounds`:
- **Arbeitsclips** (`clips`) klingen auf ihren Frames: Odriks Meißel auf dem Schlagframe, Tamsas Rad einmal je Umlauf, Besen zweimal je Zug, Pims Laterne einmal je Anzünden, Pims Polieren und das Werkeln der Statisten nur mit einer Chance.
- **Stimmen** (`voices`): Hedda summt beim Fegen, Servieren und Stehen alle 22–50 s. Händler rufen tagsüber alle 24–60 s.
- **Gemurmel** (`murmur`): eine Schleife am Gasthaus, die ab drei Leuten davor einblendet und wieder ausblendet, wenn sie gehen (`HallgratPeople._murmur`).

Abgespielt wird `HallgratResident._sounds` nur, wenn ein lokaler Spieler in Hörweite ist, und höchstens `max` (8) Sounds gleichzeitig. Ein Sound wird nach seiner Länge freigegeben.

Der Test prüft zusätzlich die Dateien, dass Odriks Meißel klingt und dass er aus der Ferne nicht klingt (1977 Checks).

**Nicht gebaut:** das Schnurren, denn die Katze aus §4 gibt es noch nicht.
