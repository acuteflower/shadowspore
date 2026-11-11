# Die Seehexe und ihr Haus am Rand (Konzept, 2026-11-11)

Status: **Alle drei Schritte gebaut (2026-11-11), siehe Abschnitt 13.** Setzt Punkt 12.4 aus `docs/magie_konzept.md` um („Die Seehexe, ihre Hütte unten links am Hexenwald-See“). Offene Entscheidungen stehen in Abschnitt 12, der Einbauplan in Abschnitt 11.

## 1. Idee in einem Satz

Am Südufer des Hexenwald-Sees, dort wo die Leere schon das Land frisst, steht ein schiefes Pfahlhaus voller klingender Kristalle. Darin wohnt die **Seehexe**: Sie fischt nachts gewachsene Kristalle aus dem See, schleift tagsüber Mondsteine am Ufer und baut daraus und aus Esmas Fluchsilber die **Zauberstäbe und Steine**, mit denen Ellie zaubert.

## 2. Warum das ins Spiel passt

- **Die Magie braucht eine Quelle.** Stab und Kristalle gibt es heute nur über das ENTWICKLER-Menü (Magie 14). Die Seehexe ist der Ort, an dem Ellie ihren ersten Stab bekommt, und ihre Einstiegsquest ist das Magie-Tutorial.
- **Zwei Hexen, zwei Handwerke** (Magie 2): Esma (Turm, Nebel, Hexengrün, Talismane und Tränke) und die Seehexe (Wasser, Ufer, Türkis und Mondstein, Stäbe und Kristalle). Jeder Stab trägt ein Band aus Fluchsilber, das von Esma kommt. Beide brauchen sich.
- **Die beiden Kristall-Sets bekommen eine Herkunft** (Magie 4.7): Zauberkristalle sind *gewachsen* und klar, also wachsen sie **nachts im Wasser**. Verstärker sind *geschliffen* und milchig, also liegen sie als **Mondsteine bei Tag am Ufer**, und sie schleift sie von Hand.
- **Licht ist Land, auch am Rand der Welt.** Ihr Haus wird von einem Ring aus Bannsteinen geschützt, einem echten Lichtkreis, den die Nacht respektiert wie die Laternen der Stadt. Er steht nur wenige Kacheln vor der Leere. Hier sieht man am deutlichsten, wie Licht gegen die Leere hält.
- **Die gefährliche Nacht am See:** Der Lichtfischer ahmt Lampen und Leuchtpflanzen nach. Wer nachts im Flachwasser nach leuchtenden Kristallen sucht, kann einen echten Kristall nicht sicher von seinem Köder unterscheiden.

## 3. Der Ort

### 3.1 Lage (gemessen an den gebackenen Karten)

- **Hexenwald-See:** Mitte (734, 908), etwa 28 × 24 Kacheln (`data/lakes.json` `hexenwald_lake`). Südlich davon liegt ein flacher Streifen Hexenwald-Boden (Biom-Byte 205, Ebene 0), dann die Küste der Leere.
- **Haus (Füße der Tür):** Vorschlag **(742, 940)**. Gemessen: Ebene 0 und 100 % eben in 11 × 13 Kacheln, **7,5 Kacheln bis zur Leere** (Süden/Südwesten), 13,5 Kacheln bis zum Seewasser (Norden). Das Haus liegt also genau zwischen See und Weltrand, unten links auf der Karte.
- **Steg:** vom Hof nach Norden bis ans Ufer, etwa (738, 930) (2 Kacheln vom Wasser). Er läuft nur über das flache, watbare Ufer. Über tiefes Wasser führt er nicht, weil die tiefe Mitte gesperrt ist (Abschnitt 12, Punkt 5).
- **Abstand zu den anderen Orten:** Esmas Turm (891, 965) liegt etwa 150 Kacheln östlich, der Krähenbaum mit dem Schieferkessel (814, 920) etwa 75 Kacheln östlich. Der See und das Haus bilden das **westliche Ende des Hexenwalds**.
- **Seepfad:** ein neuer Eintrag in `data/ground.json` `paths` (`seehexe_path`, `gloom: true` wie der `hexenwald_path`). Er zweigt vom Hexenwaldweg ab, läuft am Ostufer entlang nach Süden und endet am Hof. Die genaue Route wird beim Bau auf ebenen Ebene-0-Kacheln gewählt (Hügel bei x 760–800, y 880–930 umgehen) und mit `bake_ground.py` gebacken. Es wird keine neue Pfadkunst gezeichnet.
- `clear_radius` 12 hält generierte Bäume und Büsche vom Hof fern. Hexenwald-Pflanzen dürfen bis an den Ring heran wachsen.

### 3.2 Das Hexenhaus von außen

Ein **niedriges, breites, schiefes Pfahlhaus**: Das Ufer wird bei Regen nass, deshalb steht es auf kurzen Pfählen aus Bleichholz.

- **Holz:** Wände aus hellen, verwitterten Bleichholz-Planken (`bone_tree`), Balken und Rahmen aus dunkler Hexenulme (`hag_tree`) mit den kurzen violetten Adern. Die Materialien kommen aus der Pflanzenwelt des Hexenwalds, wie bei Esmas Turm.
- **Dach:** schweres Rohrdach aus Seeschilf (Rohrkolben gibt es schon als Pflanze), bemoost und tief heruntergezogen. Auf dem First sitzt eine Reihe kleiner Kristallspitzen, die nachts schwach türkis glimmen.
- **Fenster:** zwei runde Fenster wie Linsen. Das große zum See hin ist eine einzige gewölbte, milchige Scheibe (ein riesiger Cabochon). Nachts wirft es einen türkisen Lichtfleck auf den Hof (Lichtregeln: `docs/design_guide.md` Abschnitt 6).
- **Unter der Traufe:** **Kristall-Windspiele** an Fäden, die sich mit `WorldWind` bewegen (Zeilen-Sway wie die Wäscheleine der Hütte, `sway_rows.gdshader`) und leise klingen. Bei Sturm klingen sie lauter und unruhiger. Das greift die Windspiel-Ausrüstung des Inventars auf.
- **Anbau:** ein offenes Vordach mit dem **Tret-Schleifrad**. Es dreht sich, wenn sie draußen schleift (Schritt 3), und liegt in glitzerndem Schleifstaub.
- **Hof:** Trockengestelle mit Kristallen an Schnüren, ein Korb mit Mondsteinen, ein umgedrehter Holzkahn, ein Wasserfass, Trittsteine zur Tür (gebacken wie der Hof der Hütte: `yard` mit `trample`, `tracks`, `slabs`). Dazu ein kleiner Kahn, der am Steg vertäut ist und auf dem Wasser schaukelt.
- **Schornstein:** schmal und krumm. Der Rauch ist ganz leicht türkis getönt (Kristallstaub im Feuer).
- **Die Leerenseite:** Die Südwand ist angesengt. Dort hängen drei Spiegelscherben, die zur Leere zeigen („damit sie sich selbst sieht und erschrickt“). Zwischen Haus und Küste liegt der versengte Boden des `VoidEdge`.

### 3.3 Der Bannsteinring

- **Fünf Bannsteine**, halb versunkene Stelen aus dem violetten Stein der Wegsteine mit einem gewachsenen Kristallkopf, stehen in einem Ring von etwa **9 Kacheln** um das Haus. Die zwei Steine auf der Leerenseite sind dunkler und rissig, an ihnen sieht man den Druck der Leere.
- **Als Licht:** Der Ring meldet einen echten Lichtkreis an. Wie der Laternenkreis (Magie 5.1) wird er von `TownManager.light_depth/spawn_blocked` über einen kleinen eigenen Anbieter zusätzlich abgefragt, ohne Stadtdaten. Darin entsteht nichts, ruhige Schattenwesen gehen nicht hinein, gereizte (`excited`) dürfen hinein. Ihr Haus ist so eine kleine Festung am Weltrand.
- **Der Nebel:** Innerhalb des Rings gibt es **keine Halluzinationen** (`StatusEffects._breathe_mist` fragt den Ring ab). Wer aus dem Hexenwald hereinkommt, merkt: Hier lügt der Nebel nicht. Die Nebelstimmung selbst bleibt.
- **Aussehen:** bei Tag leises Glimmen und Kristallfunken (`g_sun`-Glitzer wie bei Kristallfelsen), bei Nacht ein Lichtband von Stein zu Stein, das am Boden entlang atmet (Herzschlag-Puls wie `VoidGlow`, aber in Türkis).
- **Zustände:** ERLOSCHEN (zu Beginn der Quest, Abschnitt 8) und WACH (danach, für immer). Gespeichert als Weltzustand wie die Wegsteine (`"lake_ring"` im Save, Host entscheidet, Snapshot für Beitretende).

### 3.4 Das Haus von innen

Ein Innenraum aus `data/interiors.json` (`lake_hut`), gebaut vom vorhandenen `Interior`, etwa 288 × 224 px, **ein Raum mit klaren Ecken**:

| Ecke | Was | Spot der Hexe |
|---|---|---|
| an der Tür | **Tresen**: niedriger Tisch mit Waage, Lupe, Samtbrett mit Steinen | `counter` |
| am Linsenfenster | **Schleiftisch** mit einem kleinen Handschleifrad, Polierschalen, Glitzerstaub | `grind` |
| an der Wand | **Schnitzbank** mit Schraubstock, Stabrohlingen aus Hexenulme, Fluchsilberdraht | `carve` |
| in der Mitte im Boden | **Resonanzbecken**: ein rundes Steinbecken mit Seewasser, darin wachsen Kristalle; das Wasser wirft wanderndes Licht auf den Boden | `basin` |
| Rückwand | **Kristallwand**: hunderte kleine Schubfächer und Fächer mit Steinen, ein Leiterchen | `shelf` |
| hinten links | Herd mit Teekessel, Bettnische hinter einem Vorhang, ein Sessel | `hearth` |

- **Boden:** Bohlen mit Spalten, durch die man unter dem Haus das Wasser flimmern sieht (eine `decal`-Ebene mit Lichtzeilen).
- **Leben:** das Becken kräuselt sich, die Windspiele drinnen klingen bei offener Tür, Staub glitzert im Fensterlicht (`rays`), eine Kröte sitzt auf dem Beckenrand (nur Deko, die Kröten des Hexenwalds), im Regen tropft es nicht (ihr Haus ist dicht, anders als die alte Hütte).
- **Licht:** warm am Herd, kühl-türkis aus dem Becken und der Kristallwand (`InteriorLight`, `_glow`-Sheets).

## 4. Die Seehexe

### 4.1 Wer sie ist

- **Name:** Vorschlag **ILVA**, Titel **SEEHEXE** (Alternativen: ODA, SENNA; „Maren“ ist schon für die Fischerei vorgesehen). Der Name wird vom Nutzer festgelegt.
- **Alter und Wesen:** älter als Esma, ruhig, geduldig, warm, oft summend. Sie redet mit Steinen und behauptet, sie höre sie singen. Sie lacht gern und laut und ist dabei etwas traurig: Sie bleibt am Rand, weil nur dort die Steine wachsen, und sie weiß, dass die Leere jedes Jahr näher kommt.
- **Gegensatz zu Esma:** Esma ist trocken, eigen, misstrauisch und lebt oben im Nebel. Ilva ist herzlich, erdverbunden und lebt unten am Wasser. Die beiden sind alte Freundinnen, die sich gern streiten („Esma hält Silber für eine Sprache. Silber ist ein Zaun.“). Diese Sätze sind nur Beispiele. Alle Texte schreibt der Dialog-Agent (`docs/prompts/dialogue_writer.md`).
- **Was sie über die Welt weiß:** Wo die Leere das Land berührt, entsteht Druck, und der Druck presst Licht im Seegrund zu Kristall. Die Kristalle sind also Licht, das die Leere zusammengedrückt hat. Deshalb wirken sie gegen Schattenwesen. Das macht die Magie zu einem Teil der Weltgeschichte, ohne die Hauptstory festzulegen.

### 4.2 Aussehen (Vorgabe für die Figuren-Kunst)

- Untersetzt und kräftig, breite Schultern, Arbeitshände. Im Rig etwas kleiner als Esma und kräftiger, gleiche Ellipsoid-Pipeline wie Esma, Gustav und Torben.
- **Haar:** aschgrau, ein dicker Zopf, als Krone um den Kopf gelegt und mit **gewachsenen Kristallnadeln** festgesteckt (die spitze, klare Form der Zauberkristalle). Nicht silberweiß, damit sie sich klar von Ellie unterscheidet.
- **Augen:** hell graublau. Eine **Juwelierlupe** an einer Kette, meist in die Stirn geschoben, beim Schleifen vor einem Auge.
- **Kleidung:** ein geölter Regenumhang in Schilfgrün über einem dunklen Petrol-Kleid mit hochgerollten Ärmeln, eine Lederschürze voller glitzerndem Schleifstaub, an der Schürze ein **Mondstein-Anhänger** (die milchige, runde Form der Verstärker), Holzpantinen, Saum nass und dunkel.
- **Haut:** wettergegerbt. An den Unterarmen einige feine, glitzernde Narben, wo die Kristalle sie berührt haben (unbeleuchtet, sehr dezent).
- **Farben:** Schilfgrün, Petrol, Mondstein-Weiß und Türkis. Abgesetzt von Esmas Wein, Knochenweiß und Violett und vom Hexengrün des Waldes. Leuchtend (Glow-Sheet) sind nur die Kristallnadeln, der Mondstein und die Lupe, die Licht fängt.
- Ihre Figur verbindet damit **beide Kristall-Sets**: gewachsene Spitzen im Haar, geschliffener Stein an der Schürze.

### 4.3 Clips (Rig-Format wie `data/witch_rig.json`, 8 Richtungen)

idle, walk, counter (Steine auf dem Samtbrett zeigen), grind (am Rad, Funken an einem `strike`-Frame), carve (Schnitzen und Silberdraht wickeln), basin (kniet, legt Steine ins Becken, hebt einen heraus), shelf (sucht in Fächern), give (Übergabe, einmalig), plus für die Quest: listen (zuhören), point (zeigt hinaus) und hold_ward (beide Hände an einem Kristall, angestrengt). Bestehende Clips werden nicht doppelt erfunden. Was Esmas Rig schon kann, dient als Vorbild für Anker und Handpunkte.

### 4.4 Tagesplan

Sie ist ein `InteriorResident` (wie Esma, `data/settlers.json` Eintrag `lake_witch`, `away: true`, von `TownManager` gekannt und vertraut, aber keine Stadtfigur):

| Zeit | Spot |
|---|---|
| Morgen | basin (holt die über Nacht gewachsenen Steine) |
| Vormittag | counter |
| Mittag | grind |
| Nachmittag | counter / carve im Wechsel |
| Abend | hearth (Tee) |
| Nacht | basin und shelf (Steine wachsen nachts, sie hütet sie) |

E = ANSPRECHEN (tägliches Vertrauen +, eine `chat`-Zeile je Spot/Nacht/Questschritt), danach HANDELN.
Ab Schritt 3 steht sie **in der Dämmerung draußen auf dem Steg** (eine erzählte Figur wie der Ritter im Steinbruch, kein Siedler-Netzobjekt) und kehrt zurück, wenn Ellie kommt.

## 5. Was sie anbietet (`data/shops.json` `lake_counter`)

`ShopWindow` mit der Bühne von `BoardWindow`, genau wie Esmas HEXENSTUBE. Rolle `lake_witch`, Station `lake_bench`, Handel nur im Raum (`TownManager.register_person/person_node/register_outpost`).

| Reiter | Art | Inhalt |
|---|---|---|
| **KAUFEN** | buy | Stufe-I-Steine (SPLITTER, ROHSCHLIFF) aller gebauten Schulen, ab Vertrauen 25 einzelne Stufe-II-Steine, leere Fassungsteile, Seeglimmer/Mondstein roh. Stufe III und höher **nie** im Laden. |
| **VERKAUFEN** | sell | Seeglimmer, Seemondstein, Leerensplitter, Schattenkerne, Fluchsilber, Glimmkappen, Leerenblüten und überzählige Kristalle |
| **STÄBE** | craft | Rezepte mit `role: "lake_witch"` in `data/recipes.json`. Der **Hexenulmenstab** (`staff_hag_elm`: Hexenulmenholz, Fluchsilber, Seeglimmer) und die **Bleichgabel** (`staff_bone_fork`, zwei Zinken: Bleichholz, Fluchsilber, Seemondstein, Schattenkern; Magie 17). |
| ~~STEINE~~ | entfernt (2026-11-11) | Steine werden nicht mehr gebaut: Rohsteine legt Ilva frei (LÄUTERN, Abschnitt 14). |
| **SCHLIFF** | eigene Art `grind` | **Stufe hoch:** 3 gleiche Steine einer Stufe + Material + Kupfer → 1 Stein der nächsten Stufe (Magie 12.3 „Verschmelzen 3 → 1“) |

**Schulmaterialien** (Vorschlag, IDs vorhanden): LICHT `glow_cap`, WURZEL `wound_leaf`, GLUT `ember_berry`, NEBEL `mist_lily` oder `ghost_frond`, LEERE `void_bloom`.

**SCHLIFF im Detail** (reine Regeln in einer neuen `CrystalRules`, wie `RefineRules`):
- **Sofort**, wie das Verfeinern seit 2026-11-09: Der Host nimmt Steine, Material und Kupfer, gibt den neuen Stein in die Tasche und zeigt eine Enthüllungskarte im Stil von `RefineReveal` (der Stein wächst aus drei Splittern zusammen).
- **Kein Fehlschlag.** Der Preis steigt mit der Stufe. Material je Ziel-Stufe: II Seeglimmer, III `void_splinter`, IV `shadow_core`, V ein Bossstein (`mora_shard` oder ein späterer Mornath-Stein).
- Stufe V nur ab Vertrauen 60. So bleibt STERNSTEIN/KRONE selten, ohne dass er im Laden liegt.
- Steine im Stab werden nicht geschliffen (vorher herausnehmen; das setzt die Ladung zurück, Magie 4.2).
- Zahlen kommen aus einer kleinen Simulation (`tools/sim_crystals.py`), wie bei `sim_refine.py`.

## 6. Die Rohsteine am See (neue Quellen)

Magie 8 sieht den See als Quelle vor. Daraus werden zwei gespiegelte Sammelstoffe, passend zu den zwei Kristall-Sets:

| Rohstein | Item | Wann und wo | Aussehen | Wofür |
|---|---|---|---|---|
| **Seeglimmer** | `lake_glimmer` | **nachts**, im Flachwasser der Seeufer, besonders auf der Leerenseite | klare, spitze Kriställchen, die unter Wasser türkis glimmen (Glow-Sheet, `bloom: "night"`) | Splitter, Stab, Schliff II |
| **Seemondstein** | `lake_moonstone` | **bei Tag**, am trockenen Ufersaum zwischen Kieseln | milchige, runde Kiesel mit sanftem Farbschimmer | Rohschliffe |

- Beides sind `Pebble`-Funde (E = SAMMELN, Pflück-Animation, wachsen nach `regrow_days` 3 nach), platziert vom `PropGenerator` über eine neue Schicht am See (`water_edge` gibt es schon, Abstand über `PropGenerator.water_dist`). Seeglimmer liegt am Uferrand im watbaren Wasser, mit Waten und Platschen.
- **Die Spannung der Nacht:** Seeglimmer leuchtet, und der Lichtfischer lockt mit einer türkisen Laterne. Am See weiß man nachts nie ganz, wohin man greift. Im Bannsteinring kann man sicher sammeln. Außerhalb liegt mehr, aber die Nacht und der Fischer warten.
- **Beim Angeln:** selten hängt ein Seeglimmer am Haken (Eintrag in `data/fishing.json`, kein Fisch).
- Die Regel „keine Tiere töten“ bleibt unberührt: Es wird nichts gejagt.

## 7. Wie sie mit dem Rest der Welt verbunden ist

- **Esma:** Ihr Fluchsilber steckt in jedem Stab. Im KAUFEN-Reiter der Seehexe gibt es kein Fluchsilber, das kauft man bei Esma. Esma verweist bei Fragen zu Stäben auf den See, die Seehexe bei Fragen zu Talismanen auf den Turm. Gegenseitige `chat`-Zeilen.
- **Valdric und Gustav:** je eine Zeile, wenn Ellie mit Stab herumläuft (Pools nach Flags).
- **Karte (M):** Marker `lake_witch` in `data/map_markers.json`, erst sichtbar, wenn die Questtafel- oder Esma-Spur gelesen wurde. Der Bannsteinring erscheint auf der Karte als kleiner türkiser Ring.
- **Questtafel:** Ein `story`-Aushang kann die Einstiegsquest anbieten (Abschnitt 8, zweiter Weg). Später (nicht hier) kann sie Aufträge geben (Seeglimmer bringen, Bannsteine prüfen).
- **Nacht:** Ihr Ring zählt für den `NightDirector` wie ein fremder kleiner Lichtkreis. Auf der Leerenseite erscheinen gern die magentafarbenen Augen der Küste. Bei Sturm schlägt der See an den Steg.
- **Wetter:** Regen macht das Ufer nass (Pfahlhaus!), Windspiele bei Sturm, Regenringe auf dem See (wenn gebaut).
- **Tag und Nacht drinnen:** Interior-Tönung warm am Tag, nachts kühl-türkis vom Becken.

## 8. Einstiegsquest „Der Ring am See“ (Vorschlag)

**Voraussetzung:** Esma ist bekannt (Turm betreten, `entered_witch_room`). Zwei Wege führen hin:
1. **Esma** sagt nach einem Gespräch (ab Vertrauen 10): Für Stäbe gehe man zum See, und sie gibt Ellie einen **Fluchsilberring** mit („Bring ihr das, sie wartet seit dem Herbst darauf.“). Das Item ist `quest: true`, nicht handelbar.
2. **Questtafel:** ein goldener `story`-Aushang („Am Westsee brennt kein Licht mehr“) startet dieselbe Quest. Den Fluchsilberring gibt Esma dann nachträglich, oder Ilva akzeptiert stattdessen einen Fluchsilberbarren (`curse_silver`).

**Ablauf** (Quest `lake_witch`, Schritte im vorhandenen Questsystem):

| # | Schritt | Typ | Was geschieht |
|---|---|---|---|
| 1 | ZUM SEE IM WESTEN | reach, `search` 30 um das Südufer | Ellie folgt dem Seepfad. Beim ersten Blick auf das dunkle Haus ein Bark (`bark:lake_dark`). |
| 2 | DAS DUNKLE HAUS | reach (Tür) | Der Ring ist ERLOSCHEN, die Tür verriegelt (`Doorway.locked`). Durch die Tür spricht Ilva (Sprechbox, ohne Porträt): Sie hält mit beiden Händen den letzten Stein im Becken wach, sonst bricht die Leere durch den Boden. Sie bittet Ellie, die **drei schwächsten Bannsteine** neu zu nähren. |
| 3 | NÄHRE DIE BANNSTEINE | tasks | Drei Aufgaben in beliebiger Reihenfolge: je einen **Seeglimmer** aus dem Flachwasser holen (hier liegen drei feste, auch bei Tag sichtbare Quest-Funde) und in einen Bannstein legen (E „NÄHREN“, `Player.begin_touch` wie an den Wegsteinen, Lichtstrahl, Klang). |
| 4 | HALTE DEN RING | flag | Nach dem zweiten Stein **reißt die Leere am Ufer auf**: zwei Schattenspinnen und ein Lauscher steigen aus der Küste (`spawn_story_spider` bzw. `spawn_species`, normale Werte, echter Kampf). Der dritte Stein lässt sich erst nähren, wenn sie tot sind. Ein normaler Tod ist erlaubt (Rückkehr an der Basis), die Quest bleibt beim Schritt, die Gegner kommen beim nächsten Nähern wieder (feste Begegnung, kein Doppeln). |
| 5 | DER RING ERWACHT | flag (Szene) | Der dritte Stein: Das Lichtband läuft von Stein zu Stein und schließt sich. Der Boden der Leerenseite glüht kurz auf und weicht zurück. Die Tür springt auf, Ilva kommt erschöpft heraus. Zustand WACH für die Welt. |
| 6 | SPRICH MIT DER SEEHEXE | dialogue (`story:lake_meet`) | Erstes Gespräch drinnen: Wer Ellie ist, Esmas Ring (wird abgegeben), was Kristalle sind (Abschnitt 4.1, kurz). Bekannt-Flag `knows_lake_witch` (Silhouette bis dahin, wie bei Valdric). |
| 7 | EIN STAB FÜR DICH | Szene | Ilva baut den Stab vor Ellies Augen: schnitzen, Silber wickeln, Kristall wachsen lassen (Zeitraffer mit Schwarzblende wie beim Hüttenfinale, 3–4 kurze Einstellungen). Übergabe: **Hexenulmenstab** + **Bannlicht-SPLITTER** + **Brennglas-ROHSCHLIFF**. |
| 8 | SETZE DIE STEINE EIN | tasks + `hint: "socket"` | Neue `HintCard`: Stein auf den Cursor, auf den Stab klicken, Rechtsklick nimmt heraus. Erledigt, wenn beide Fassungen belegt sind. |
| 9 | WIRKE DEN ZAUBER | flag + `hint: "cast"` | Stab wählen, LMT. Draußen am Ring hat Ilva eine **Übungsschale** (ein Schatten in einem Glasgefäß, die Übungspuppe mit Schattenaussehen) aufgestellt, die das Bannlicht verbrennt. Flag `first_cast`. |
| 10 | Abschluss | – | Ilva: Der Laden ist offen, Steine wachsen am See, „komm wieder, wenn du drei gleiche hast“. HANDELN ist frei, Kartenmarker gesetzt. |

- **Der ENTWICKLER-Knopf** „ZAUBERSTAB + ALLE KRISTALLE“ bleibt. Neu: ENTWICKLER → QUEST-TESTS → SEEHEXE (Start, Neustart nur dieser Quest) und STORY-SPRUNG → SEEHEXE BEKANNT (Ring wach, Quest erledigt, Stab in der Tasche).
- **Mehrspieler:** Ring und Kampf entscheidet der Host. Der Ring ist Weltzustand: Wer später kommt, findet ihn wach, und seine Quest springt von Schritt 2 direkt zu Schritt 6 („Jemand war schneller als du. Gut so.“). Stab und Steine gibt es **einmal pro Spieler** (wie das Schwert des Ritters: eigenes `ItemDrop` mit `story_owner`, gespeichert unter `story`).
- **Alle Texte sind Platzhalter** für den Dialog-Agenten.

## 9. Ton (`tools/audio_lake_hut.py`, synthetisierte Platzhalter)

Kristall-Windspiele (vier Töne, zufällige Folgen, leiser bei Windstille), Schleifrad (gleichmäßiges Schleifen mit Glitzern an den Spitzen), Becken (Tropfen, tiefes Glucksen, ein heller Ton, wenn ein Stein „fertig“ ist), Steg-Knarren und Wasser am Pfahl, Bannstein nähren (aufsteigender Ton, beim dritten ein Akkord), Ring erwacht (Akkord und das Zurückweichen der Leere), Tür, Raumklang-Ambiente (Herd und Wasser unter den Bohlen), Ilvas Summen (ein paar Takte für Zeilen).

## 10. Technik in Kürze

| Teil | Wo |
|---|---|
| Haus außen | `Hut` mit neuem `LOOKS`-Eintrag `lake` (Bild, Türblatt, Kollider, Rauch, Lichter), Eintrag in `data/ground.json` `huts` (`art: "lake"`, `interior: "lake_hut"`, `yard`) |
| Hof, Steg, Kahn, Windspiele | `HutYard`-Props mit `layers`-Sway, Kunstordner `assets/props/lake_hut/` |
| Bannsteinring | neuer Knoten `WardRing` (Kind von `WorldLevel`, Gruppe `ward_rings`): fünf Steine, Zustand, Lichtanbieter für `light_depth/spawn_blocked`/`lit_circles`, Nebelfreiheit für `StatusEffects`, Snapshot, Save-Schlüssel `"lake_ring"` |
| Innenraum | `data/interiors.json` `lake_hut` (aus dem Kunstskript erzeugt wie `witch_room`), `resident`-Schlüssel |
| Die Hexe | `InteriorResident`, `data/settlers.json` `lake_witch`, Rig `data/lake_witch_rig.json`, `DialogueBox.LATE_PORTRAITS`/`TALKING_PORTRAITS` |
| Laden | `data/shops.json` `lake_counter`, Rezepte `role: "lake_witch"`, neue Reiterart `grind` in `ShopWindow` |
| Regeln | `CrystalRules` (rein): Schliffkosten, Zielstufe, Prüfungen; `TownManager.request_grind` (Host) |
| Rohsteine | Items `lake_glimmer`, `lake_moonstone` (+ Icons), `plants.json`-Einträge mit `pickup`, `PropGenerator`-Schicht `lake_stones` (niedrige Priorität, verdrängt nichts, nur an Seeufern) |
| Quest | `data/quests.json` `lake_witch`, `data/dialogue.json`, Szenen `LakeWardScene` (Schritte 4–5) und `StaffMakingScene` (Schritt 7), `HintCard` Fälle `socket`/`cast` |
| Kunst | Hof/Haus/Ring/Steg: `py -3 tools/art_lake_hut.py [preview.png]`; Innenraum: `py -3 tools/art_lake_hut_inside.py [preview.png]`; Figur: `py -3 tools/art_lake_witch.py [sheet.png]`; Rohsteine im vorhandenen `tools/art_crystals.py` |
| Tests | `tools/test_lake_hut.tscn` (Schritt 1), `tools/test_lake_witch.tscn` (Schritt 2, Laden/Schliff/Speichern), `tools/test_lake_quest.tscn` (Schritt 3, inkl. Tod, Neustart, späterer Mitspieler, volle Tasche); Vorschau `tools/preview_lake_hut.tscn -- --dir=/abs [--night] [--inside]` |

**Wer macht was** (Projektregeln): Alle neue Kunst entsteht über den `gpt-6.1-terra`-Subagenten. Figur und Porträt der Seehexe macht der Figuren-Agent nach `docs/dialogue_art.md`, Texte der Dialog-Agent. System, Einbau und Prüfung bleiben beim Haupt-Agenten.

## 11. Einbauplan in drei Schritten

Jeder Schritt ist für sich spielbar und prüfbar. Die Reihenfolge folgt dem Muster von Esmas Einstieg: zuerst der Ort, dann die Figur, dann die Quest.

### Schritt 1 – Der Ort: Haus, Ring und See (ohne Hexe)

- Ort festlegen und prüfen (Abschnitt 3.1): Haus (742, 940), Steg, Ring mit 9 Kacheln, `clear_radius`, Seepfad vom Hexenwaldweg gebacken (`bake_ground.py`, dann `--yards` für den Hof).
- Kunst: Haus außen (frisch und dunkel/verlassen), Hof, Steg, Kahn, Windspiele, fünf Bannsteine in zwei Zuständen, Innenraum mit allen Ecken (Becken, Schleiftisch, Schnitzbank, Kristallwand, Herd), Glow-Sheets.
- Einbau: `Hut`-Look `lake`, `HutYard`, Innenraum mit Tür, `WardRing` mit Lichtanbieter, Nebelfreiheit und Save. Zu Beginn ist der Ring **wach** (der Quest-Zustand ERLOSCHEN kommt erst in Schritt 3), damit der Ort sofort benutzbar ist.
- Rohsteine: Items, Icons, `Pebble`-Funde Seeglimmer/Seemondstein mit der Seeufer-Schicht, Angelfund.
- Ton der Umgebung (Windspiele, Wasser, Raumklang).
- **Abnahme:** Haus bei Tag/Nacht/Regen/Sturm und im Nebel ansehen, Kollision und Verdeckung, Tür rein/raus, Ring blockiert Nachtgeburten und Halluzinationen, Rohsteine sammeln und nachwachsen lassen, Streaming und Speichern. `test_lake_hut.tscn`.

### Schritt 2 – Die Seehexe: Figur, Tagesplan, Laden

- Figur (Sheet, Glow, Rig) und Porträt mit Lippenbewegung, Platzhalter-Zeilen.
- `InteriorResident` mit Tagesplan (Abschnitt 4.4), ANSPRECHEN/HANDELN, Vertrauen.
- Laden `lake_counter`: KAUFEN, VERKAUFEN, STÄBE, LÄUTERN, SCHLIFF; `CrystalRules`, `request_grind`, Enthüllungskarte, Balance-Simulation.
- Gegenseitige Zeilen mit Esma (und Valdric/Gustav).
- Kartenmarker.
- Bis Schritt 3 ist sie über ENTWICKLER → SEEHEXE KENNEN ansprechbar.
- **Abnahme:** jeden Spot und jeden Clip in den nötigen Richtungen ansehen; jeden Reiter kaufen/verkaufen/bauen/schleifen lassen, auch mit voller Tasche, ohne Kupfer und mit Steinen im Stab; Mehrspieler-Handel über den Host. `test_lake_witch.tscn`.

### Schritt 3 – Die Einstiegsquest „Der Ring am See“

- Quest, Dialoge, Barks, Hinweise in Esmas Zeilen und am Brett.
- Ring-Zustand ERLOSCHEN für Spieler ohne Quest-Abschluss in einer Welt, in der der Ring noch nie erwacht ist. Szenen „Halte den Ring“ (Kampf an der Küste) und „Ein Stab für dich“ (Zeitraffer).
- HintCards `socket` und `cast`, Übungsschale, Belohnung pro Spieler einmal.
- Ilva in der Dämmerung auf dem Steg (erzählte Außenfigur).
- ENTWICKLER: QUEST-TESTS → SEEHEXE, STORY-SPRUNG → SEEHEXE BEKANNT.
- **Abnahme:** einmal komplett vom Brett und einmal von Esma bis zum ersten Zauber spielen; zusätzlich Tod im Ringkampf, Neuladen mitten im Kampf, ein zweiter Spieler kommt später, volle Tasche bei der Übergabe, Stab schon vorhanden (Dev). Texte und Kampfgefühl erst nach diesem Durchlauf festlegen. `test_lake_quest.tscn`.

## 12. Offene Entscheidungen

1. **Name** der Seehexe (Vorschlag ILVA).
2. **SCHLIFF-Regel:** 3 gleiche → 1 höhere Stufe ohne Fehlschlag (Vorschlag), oder 2 + seltenes Material, oder ein Wachstum über Benutzung (Magie 12.3).
3. **Wann man sie findet:** nach Esma (Vorschlag) und/oder über die Questtafel; ob es eine Stufen-Schwelle gibt (z. B. Stufe 5 wie bei der Spiegelhexe).
4. **Nebelfreiheit im Ring:** ja (Vorschlag) oder nur weniger Halluzinationen.
5. **Steg bis ins tiefe Wasser** (zum Angeln vom Stegende): braucht eine Ausnahme in der Tiefwasser-Kollision und kommt deshalb frühestens nach Schritt 3.
6. **Eigene Tränke der Seehexe** (Magie 12.4: Wurftränke): bewusst **nicht** in diesem Konzept.

## 13. Gebaut (2026-11-11)

### Schritt 1: der Ort
- **Haus** bei Kachel **(738, 936)** (nach dem Messen näher ans Ufer gerückt: 7,5 Kacheln bis zum See, 9 bis zur Leere). `Hut`-Look `lake` (`src/entities/props/hut.gd` LOOKS: Bild, Tür, Kollider, türkiser Rauch, Linsen-Lichtfleck `spill`, `lamps`, Windspiele `hangs`, Schleife `sounds`, Dachplätze für Krähen). Das Haus ist ein echter Körper, leicht gedreht (`YAW`), mit sichtbarer Seitenwand, Walm-Reetdach mit Überstand, Kristallbüschel durchs Dach, Mondsichel-Stange, Laternen, Runen an den Türpfosten, Kerzen auf der Treppe, Netz mit Schwimmern, Flaschen und Bündel unter der Traufe.
- **Hof** (`data/ground.json` huts `lake_hut`, gebacken als `lake_hut_yard` mit `gloom` und eigenem `seed_index`, damit ältere Höfe unverändert bleiben): Steg mit Wasserplätschern, Kahn, Tret-Schleifrad, Trockengestell mit schwingenden Kristallschnüren.
- **Seepfad** `seehexe_path` (zweigt bei (821, 811) vom Hexenwaldweg ab, läuft am Ostufer nach Süden).
- **Bannsteinring** größer als geplant: **neun Steine auf einem Oval** um Haus, Hof und Steg (Lichtkreis 250 px um (0, -40) vom Haus), Steine 1,75-fach groß mit schwebenden Splittern; `WardRing` (src/world/ward_ring.gd): Lichtkreis über `TownManager.add_magic_light`, `WardRing.shelters` (keine Halluzinationen), Lichtband mit Runen und Herzschlag, Stein-für-Stein-Erwachen mit Klang, Host-Zustand, Snapshot, Save-Schlüssel **`ward_rings`** (statt `lake_ring`).
- **Innenraum** `lake_hut` (aus `tools/art_lake_hut.py`): kühl-violettes Holz, leuchtender Runenkreis mit Siebenstern um das Resonanzbecken (Herzkristall, Ripples, aufsteigende Funken), Kristallwand, Trankregal, Schleiftisch, Schnitzbank, Astrolabium, Mondkarte, Mondphasen-Mobile, Kerzengruppen, Besen, Herd.
- **Rohsteine**: `lake_glimmer` (nur nachts, `night_only` in plants.json, `Pebble`) und `lake_moonstone`, Schicht `lake_stones` im `PropGenerator` (`LAKE_KINDS`, nur Hexenwald-Ufer, Priorität -1 = verdrängt nichts).
- Ton: `py -3 tools/audio_lake_hut.py` (Windspiele, Wasser, Stein erwacht, Ring schließt sich).
- Test `tools/test_lake_hut.tscn` (`LAKE HUT OK`), `test_hexenwald.tscn` weiter grün.

### Schritt 2: die Seehexe
- **Figur** `py -3 tools/art_lake_witch.py [sheet.png]` -> `assets/characters/lake_witch.png` (+`_glow`), `data/lake_witch_rig.json` (Esmas Format, 76 x 96, Clips idle, walk, grind, carve, basin, counter, talk, listen, point, give). Mittleres Aschgrau statt Silberweiß, damit sie nie wie Ellie wirkt. Gemacht vom Haupt-Agenten (der Terra-Agent war nicht verfügbar). Porträt fehlt noch.
- **Bewohnerin** `lake_witch` in data/settlers.json (`away`, Tagesplan Becken, Tresen, Rad, Schnitzbank, Herd, Regale), Raum-Schlüssel `resident`. Alle Zeilen sind Platzhalter.
- **Laden** `lake_counter` (data/shops.json): KAUFEN, VERKAUFEN, STÄBE (Craft-Reiter mit `group`, Rezepte `role` lake_witch in data/recipes.json; der Reiter STEINE und seine Rezepte sind entfernt), LÄUTERN, SCHLIFF (neue Reiterart `grind`, `CrystalRules`, `TownManager.request_grind`; Kristalle mit Seeglimmer, Verstärker mit Seemondstein, Stufe III-V mit Leerensplitter, Schattenkern, Morwennas Scherbe) und **DEV** (Reiterart `dev`, `TownManager.request_dev_give`: jeder Stab, Kristall und Verstärker und die Rohstoffe gratis; wird später entfernt).
- ENTWICKLER -> **ZUR SEEHEXE** setzt Ellie vor die Tür.
- Test `tools/test_lake_witch.tscn` (`LAKE WITCH OK`).
- **Nicht gebaut:** Porträt und Sprechen-Mundformen, Enthüllungskarte beim Schliff (nur Hinweis und Klang), Ilva draußen auf dem Steg.

### Schritt 3: die Einstiegsquest „Der Ring am See"
- **Start (Entscheidung 2026-11-11):** nur über die **Questtafel**, Aushang `lake_witch_notice` „AM WESTSEE BRENNT KEIN LICHT" (data/board.json `story`), erst wenn **Esmas Quest `spiegelhexe` abgeschlossen** ist und Ellie **Stufe 10** hat (neuer Story-Schlüssel `min_level`, `BoardRules.story_due(.., level)`). Der Weg über Esma entfällt.
- **Quest `lake_witch`** (data/quests.json): `lw_lake` Haus finden (Suchkreis) -> `lw_door` ANKLOPFEN (`StorySpot` an der verschlossenen Tür, Dialog `lw_door`: Ilva hinter der Tür gibt **drei Seeglimmer**) -> `lw_feed` Aufgaben: drei rissige Bannsteine nähren (E NÄHREN, `WardFeedSpot`, ein Seeglimmer je Stein) und die Schatten vertreiben -> `lw_enter` -> `lw_meet` (E SPRECHEN bei Ilva: Hexenulmenstab, Bannlicht-Splitter, Brennglas-Rohschliff, ihr Name wird bekannt) -> `lw_socket` (Hinweiskarte `socket`) -> `lw_cast` (Hinweiskarte `cast`, `SpellComponent.cast_done`) -> `lw_end` (letztes Gespräch).
- **Der Ring schläft jetzt bis zur Quest** (`start_awake` false), die Tür ist so lange verschlossen. Nach dem zweiten Stein reißt die Küste auf: zwei Schattenspinnen und ein Lauscher (`ambush` im Ring-Block, echter Kampf, `spawn_species` mit Geburt); der dritte Stein nimmt seinen Glimmer erst, wenn sie fort sind; dann erwacht der Ring Stein für Stein, die Tür öffnet sich. Host entscheidet (`WardRing.request_feed`, `fed`/`ambush` an alle und an Beitretende).
- `LakeWitchStory` (src/world/lake_witch_story.gd) setzt die Aufgaben-Flags (alle beginnen mit `lake_witch_`, damit ein Neustart sie löscht), spielt die Barks, sperrt/öffnet die Tür und stellt nach dem Laden die genährten Steine aus den Flags wieder her (ein nicht gewonnener Kampf: der zweite Stein muss neu).
- Gespräch-Schritte bei Bewohnern: Schrittschlüssel `talk_to` + `talk` (`InteriorResident._quest_talk`, Prompt SPRECHEN statt HANDELN).
- Ilvas Zeilen laufen unter dem Sprecher `ILVA` (bis zur Vorstellung „???", kein Porträt; `DialogueBox.LATE_PORTRAITS` erwartet `assets/ui/portrait_lake_witch.png`). Alle Texte sind Platzhalter.
- Entwickler: ENTWICKLER -> SEEHEXE: QUEST STARTEN (Ring schlafend, Quest neu, Ellie am Pfad) und SEEHEXE BEKANNT (alles erledigt, Stab in der Tasche).
- Test `tools/test_lake_quest.tscn` (`LAKE QUEST OK`, 38 Prüfungen); `test_lake_hut`, `test_lake_witch` angepasst und grün. `test_board.tscn` hatte schon vorher Fehler (Wind, Tagebuch), unabhängig von dieser Arbeit.
- Bekannte Grenze: `HintCard` zeigt nur den Hinweis der ersten laufenden Quest; läuft gleichzeitig eine ältere Quest, erscheinen die Karten `socket`/`cast` nicht.

## 14. Rohsteine verbergen ihren Stein (LÄUTERN, gebaut 2026-11-11; früher AUFFRISCHEN)

Seeglimmer und Seemondstein sind Rohsteine: **schon beim Finden** steht fest, welcher Stein in jedem steckt. Ilva frischt ihn auf, dann sieht man ihn und bekommt ihn so, wie er ist.

- **Was drin stecken kann** (`items.json` Schlüssel `hidden` am Rohstein): Seeglimmer -> ein Zauberkristall (Bannlicht, Wurzelgrund, Glutschwarm, Nebelschleier, Leerenschlund, gleich wahrscheinlich), Seemondstein -> ein Verstärkerstein (Brennglas, Wildwuchs, Zunder, Dunst, Hunger). Stufe nach Gewicht: I 74, II 20, III 5, IV 1 (V nie: die gibt es nur über SCHLIFF).
- **Der Wurf** (`CrystalRules.roll`): der Host würfelt für jeden Rohstein in dem Moment, in dem er in einen Rucksack kommt (aufheben, kaufen, geschenkt, DEV). `InventoryComponent.hidden` hält je Rohstein-Art eine Liste der Würfe und gleicht sie bei jeder Änderung an (`sync_hidden`: neue Steine bekommen ihren Wurf, verbrauchte, verkaufte, geworfene oder eingelagerte nehmen den jüngsten Wurf mit). Die Steine stapeln weiter ganz normal, die Würfe sieht niemand, also verrät auch nichts, welcher Stein gegangen ist. Gespeichert als `raw_rolls` im Spielerblock (auch für Gäste), nie an Clients geschickt.
- **LÄUTERN** (Reiter bei Ilva, `shops.json` `lake_counter.refresh`: **kostenlos**, Gebühr 0, im Reiter wird kein Geld angezeigt; Ilva wäscht den Stein im See): `TownManager.request_refresh(shop, rohstein, anzahl)` -> Host prüft Nähe und Anzahl (`CrystalRules.refresh_block`), nimmt die ältesten Würfe (`take_hidden`), gibt die Steine (voller Rucksack: ins Lager der Stadt). E läutert einen, ALLE / Shift alle. `StoneReveal` (src/ui/stone_reveal.gd) zeigt den Moment: der Rohstein zittert, die Kruste bröckelt, ein Blitz, dann die Steine, der beste mit Stufe und Namen (Stufe III+ mit dem langen Klang der Verfeinerung).
- Wer die Rohsteine stattdessen verbraucht (Bannsteine nähren, Rezepte, SCHLIFF-Material, Verkauf), verliert, was darin steckte.
- Zahlen sind ein erster Wurf. Test: `tools/test_lake_witch.tscn` (52 Prüfungen, Bild `-- --capture=/abs` -> 2_refresh_card.png).
