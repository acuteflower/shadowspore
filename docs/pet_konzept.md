# Gefiederte Freunde – Pet- und Bindungssystem (Konzept)

Status: **nur Konzept, nichts gebaut.** Erste Tierarten: Krähe und Rabe (`crow`, `raven`, `WildCorvid`). Der Aufbau ist artunabhängig, damit später Eule, Wiedehopf, Fuchs, Reh usw. nur noch einen `pet`-Block in `data/wildlife.json` brauchen.

Alle Texte, Namen und Zahlen sind Platzhalter bis zum Balancing (Abschnitt 14).

---

## 1. Kernidee in einem Absatz

Ellie hält passendes Futter in der Hand, schleicht sich an eine wilde Krähe oder einen Raben heran und streckt die Hand aus. Der Vogel entscheidet selbst, ob er kommt. Jedes Füttern baut eine **Bindung** zu genau diesem Vogel auf. Ab einer Schwelle wird er zu **einem bestimmten Tier**: Er bekommt einen Namen, eine Anzeige, ein Revier in der Welt und bleibt dort, bis man ihn wiederfindet. Mit genug Bindung folgt er ihr als **Gefährte**, hilft auf seine Art (Kundschafter, Sammler, Warner) und erzählt über kleine Geschenke und Gesten eine eigene Geschichte.

**Designsäulen**

1. **Verdienen, nicht klicken.** Nähe, Geduld und das richtige Futter zählen. Kein Dauerklicken, kein Minigame mit Balken.
2. **Der Vogel ist ein Charakter.** Jeder hat Eigenschaften, Vorlieben, eine Stimme. Man liest ihn am Verhalten, nicht an Zahlen.
3. **Er bleibt in der Welt.** Er verschwindet nicht beim Chunk-Unload. Er hat ein Revier, einen Tagesablauf und ist wiederzufinden.
4. **Nie bestrafend.** Man kann ihn nicht töten oder verlieren. Vernachlässigung kostet höchstens Nähe, nie den Vogel.
5. **Multiplayer-first.** Der Host entscheidet, jeder Spieler hat seine eigene Beziehung.
6. **Passt zur Spielwelt.** Vorhandene Systeme werden zu Futterquellen und Anlässen (Angeln, Käfer ablesen, Beeren, Stadt, Nacht), statt neue Parallelwelten zu bauen.

---

## 2. Das Spielgefühl: eine Begegnung von außen nach innen

1. Ellie sieht eine Krähe auf dem Boden picken. Sie hat Dunkelbeeren im Hotbar-Slot.
2. Sie schleicht (Sneak). Die Krähe merkt es, bleibt aber auf Abstand (bisheriges Verhalten).
3. Innerhalb von etwa 48 px erscheint am Vogel der Hinweis **„E FÜTTERN“** mit Tastenkappe, und der Cursor wird zur Feder-Hand.
4. E drückt sie in die Hocke und hält die Beere hin. Der Vogel legt den Kopf schief, hüpft näher, bleibt stehen, tritt zurück, kommt wieder. Das ist die Spannung. Bewegt sie sich zu hastig oder wird laut, flattert er auf. Bleibt sie ruhig, pickt er die Beere aus der Hand.
5. Ein kurzer, leiser Ton, eine kleine Feder-Funkenspur. Über dem Vogel wächst für einen Moment eine Anzeige mit einem ersten Federchip.
6. Er bleibt noch kurz, putzt sich (Zeichen von Entspannung), fliegt auf. Beim nächsten Mal wartet er vielleicht schon.

Wichtig: Nach dem ersten Mal merkt man sofort, dass dieser Vogel jetzt jemand ist.

---

## 3. Stufen der Beziehung

Pro Vogel und Spieler gibt es **Bindungspunkte** (BP). Sechs Stufen. Die Schwellen sind Startwerte.

| Stufe | Name | ab BP | Was ändert sich |
|---|---|---|---|
| 0 | **Fremd** | 0 | Normales Wildtierverhalten. Futter aus der Hand wird nicht angenommen, nur von Weitem erkannt (Kopfdrehen). |
| 1 | **Beäugt** | 10 | Duldet Ellie bis etwa halbe Fluchtdistanz. Nimmt Futter vom Boden an (geworfen mit Q). Noch keine Anzeige im Dauerbetrieb. |
| 2 | **Bekannt** | 40 | **Wird registriert**: eigene ID, Name, Revier, Anzeige, Karteneintrag, Buchseite. Nimmt aus der Hand. Verlässt seinen Schwarm. |
| 3 | **Vertraut** | 100 | Begrüßt sie in seinem Revier mit Ruf und Anflug. Flieht nicht mehr vor Sprint und Schwertschwüngen. Wechselt ggf. in die Stadt. **Mitbringsel** beginnen. |
| 4 | **Freund** | 190 | Kommt auf **Pfiff** aus Hörweite, begleitet sie für eine Weile (Besuch). Bekommt Platz in der Stadt (Sitzstange). Erste Gabe. |
| 5 | **Gefährte** | 300 | Darf **dauerhaft begleiten**, sitzt auf der Schulter, alle Gaben, eigene Befehle. |

Ziel: Gefährte nach etwa **8–10 Spieltagen (rund zwei Stunden)** regelmäßiger Pflege. Mit Lieblingsfutter und passender Eigenschaft schneller, mit Pause langsamer, aber nie auf Null zurück (siehe 6).

Stufen sind Meilensteine mit Zeremonie: Bei Stufe 2, 4 und 5 gibt es eine kleine Szene (Kamera rückt kurz an, leiser Akkord, Banner „RUSS VERTRAUT DIR“).

---

## 4. Der Vogel als Individuum

Beim Entstehen eines Vogels (bzw. beim ersten Füttern) wird aus seiner Welt-ID ein stabiler Seed gerollt:

- **Aussehen:** Art, Gefieder-Variante (existiert, 3 pro Art), plus ein **Fußring** in einer Farbe, sichtbar ab Stufe 2 (Erkennungszeichen, siehe 9.3).
- **Eigenschaften (2 von etwa 8):**
  - *Neugierig* – nähert sich schneller, lernt auf neuen Wegen. Schwächer: wird eher abgelenkt.
  - *Scheu* – braucht länger, wird dafür später sehr treu (höhere Endwerte bei Gaben).
  - *Gierig* – Futter wirkt stärker, aber der Tagesdeckel (6) greift härter. Bettelt.
  - *Glitzerliebhaber* – Mitbringsel häufiger, mag glänzende Dinge (Rabe häufiger).
  - *Mutig* – bleibt bei Kämpfen, schwächere Panik. Greift als Begleiter eher an (Ablenken).
  - *Schwatzhaft* – ruft viel, Warnungen früher, aber auch Fehlalarme.
  - *Ruhig* – kaum Panik, gleichmäßiger Fortschritt.
  - *Nachtschwärmer* – bleibt länger wach in der Dämmerung, Nachtwarnungen besser.
- **Geschmack:** je Art 1 Lieblings- und 1 Hassfuttergruppe, plus eine persönliche Lieblingszutat (Seed). Der Rest ist „mag“ oder neutral.
- **Stimme:** jeder Vogel hat eigene Tonhöhe und Rufmuster (Seed → Pitch-Offset, Pausenrhythmus). Man erkennt ihn mit geschlossenen Augen.
- **Name:** automatisch aus einem Namenspool, bei Stufe 2 umbenennbar (Eingabefeld wie das Teleport-Feld). Pool z. B. Krähen: *Russ, Pech, Kohl, Aschen, Flick, Strubbel*; Raben: *Mondgrau, Schwinge, Nacht, Dornig*.

Eigenschaften werden **nicht** als Liste gezeigt, sondern entdeckt (Verhalten, Notizen im Buch, Abschnitt 9.4).

---

## 5. Füttern im Detail

### 5.1 Futter

Futter sind normale Items, die in `data/pets.json` als `food` eingetragen sind. Jeder Eintrag hat Gruppe und Wirkung je Art.

| Gruppe | Items (heute vorhanden) | Krähe | Rabe |
|---|---|---|---|
| Beeren | `dusk_berry`, `ember_berry` | mag | neutral |
| Samen | `seed_fluff`, `sun_seed` | **liebt** | mag |
| Insekten | `shimmer_beetle`, `leaf_caterpillar`, `leaf_snail` | mag | mag |
| Fisch | `fish_silverling`, `fish_loach` (nur kleine Fische) | neutral | **liebt** |
| Wurzeln/Knollen | `earth_tuber`, `night_beet` | neutral | neutral |
| Pilze | `glow_cap` | mag nicht | mag nicht |
| Später | gekochte Gerichte aus Kochen v2 (Krümel), Käse, Nüsse | – | – |

Dadurch wird Bestehendes sinnvoll: **Käfer und Raupen ablesen (E)**, Angeln, Beeren und Samen sammeln erhalten einen zusätzlichen Zweck. Keine neue Futterwirtschaft nötig.

Technisch: Das Item muss in den Hotbar-Slot dürfen (`"hotbar": true` für die Futteritems ohne bisherigen Hotbar-Eintrag). Alternative, falls das den Hotbar-Sinn verwässert: ein Werkzeug **Futterbeutel** in der Hotbar, aus dem ein Futtertyp per Taste (wie Köder, Z) aus dem Rucksack gewählt wird. Empfehlung: erst Variante A (Item in der Hand), wie gewünscht.

### 5.2 Wege, Futter anzubieten

1. **Aus der Hand** (ab Stufe 2 zuverlässig, davor riskant): E am Vogel mit Futter im gewählten Slot. Das Prompt des Vogels schlägt das Essen (wie bei Beerenbüschen: der Interactable gewinnt).
2. **Hinwerfen** (Q, vorhandenes `item_throw`): ein Futterstück liegt auf dem Boden. Der Vogel prüft es, wenn Ellie weit genug weg ist und seine Stufe >= 1 ist. Das ist der Weg für scheue Tiere, und man kann **mehrere Vögel** gleichzeitig anlocken. Ein Futterstück pro Vogel pro Anflug.
3. **Futterstelle** (Stadtstück, Phase 4): automatisches Anbieten aus dem Lager.

### 5.3 Annahme-Logik („willingness“)

Beim Hinhalten läuft ein versteckter **Mut-Wert** des Vogels: Er steigt, solange Ellie still steht und die Hand ausgestreckt ist, und fällt bei Sprint, Schwung, Lärm, schneller Annäherung oder anderen Bedrohungen. Beim Schwellenwert pickt er zu. Die Dauer hängt von Stufe, Eigenschaft (Scheu/Neugierig), Hunger und Futter ab: grob 1 s (Freund) bis 6 s (Fremd, Scheu). Dabei sind vorhandene Hearing-/Sichtmultiplikatoren (`sneak_multiplier`, `sprint_multiplier`, `swing_range`) wiederverwendbar.

Sichtbare Zeichen (keine Balken): Kopf schief, Schritte näher/weg, Flügel halb auf, Blick zur Hand, Putzen (entspannt), Flügel auf (gleich Flucht).

### 5.4 Reaktion auf das Futter

| Reaktion | Wirkung | Zeichen |
|---|---|---|
| **Liebt** | BP stark, evtl. Eigenschaft deutlich sichtbar | schneller Anflug, kurzer Rufton, Flügelzittern |
| **Mag** | BP normal | pickt direkt |
| **Neutral** | BP wenig | pickt zögerlich |
| **Mag nicht** | kein BP, Item wird nicht verbraucht | wendet den Kopf ab, schnippt weg |
| **Satt** | der Tag ist durch (Deckel) | schüttelt, wendet sich ab, „satt“-Zeichen |

Das Item wird nur bei Annahme verbraucht. **Ablehnung kostet kein Futter und keine Bindung.**

---

## 6. Bindungsrechnung

Reine Funktionen in `PetRules`.

**Pro Fütterung** (Basis): Liebt 12, Mag 7, Neutral 3, Mag nicht 0.

**Tagesdeckel** (verhindert Spam, belohnt Wiederkommen): Pro Vogel, Spieler und Spieltag zählt die erste bis dritte Fütterung voll, die vierte bis sechste halb, danach 10 %. Zusätzlich 20 s Pause pro Vogel nach einer Fütterung.

**Modifikatoren:** Hunger (frühmorgens bis +30 %), Eigenschaft (Neugierig +10 %, Gierig +30 % aber härterer Deckel), Wetter (Regen: Vögel sitzen unter Dach, kaum Annahme), Tageszeit (nachts schläft der Vogel, kein Füttern), Stufe (je höher, desto kleiner die Zuwächse pro Fütterung, dafür gibt es zusätzliche Wege, siehe unten).

**Zusatzquellen:**
- *Beobachten:* Wer 20 s ruhig in 4 Tiles Abstand schleicht, ohne zu füttern, bekommt +1 BP pro Tag (Belohnung für Geduld, nützlich für Fremd → Beäugt).
- *Gemeinsame Erlebnisse* (ab Stufe 3): Lagerfeuer-Sitzen in der Nähe, gemeinsam eine Nacht überstanden (Raid am Stadtlicht), Angeln mit Vogel in Reichweite: je +2 BP, einmal pro Tag.
- *Geschenke an den Vogel* (ab Stufe 3): glänzende Dinge (Glitzer-Eigenschaft), Federn der eigenen Art wieder zurückgeben (liebevolle Geste, ein Lore-Gag).

**Abnahme:** Nach 3 Tagen ohne Kontakt sinkt die Nähe sehr langsam (-3 BP pro Tag), **nie unter die Schwelle der aktuell erreichten Stufe minus 1**, und nie unter Stufe 2 bei registrierten Tieren. Wer lange weg war, wird mit Rufen und Anflug begrüßt, nicht bestraft. Gefährten bleiben Gefährten.

**Vertrauensverlust (Aktionen):**
- Hinter dem Vogel hinterherjagen/Sprint ins Revier bei Stufe < 3: kurze Flucht, kein BP-Verlust.
- Schwertschwung, der den Vogel *nahe* verfehlt (innerhalb des Schwungradius): bei Stufe ≤ 2 Vertrauen -2, bei höheren nichts.
- Kein Schaden am Vogel möglich: er hat keine Hurtbox (wie alle Wildtiere).

---

## 7. Das Tier bleibt in der Welt

### 7.1 Registrierung

Bei Stufe 2 (Bekannt) legt der Host einen **Pet-Eintrag** in `PetRegistry` an:

```
id, species, appearance, name, traits[], tastes{loves[], hates[], seed_item},
ring_color, voice, bonds{player_uid: bp}, home{tile, perch_id|null},
last_seen{pos, time}, mood{day, fed_today}, companion_of, mode, injured_until,
stats{feeds, days_known, gifts}, diary[]
```

Ab dann ist es ein **fester Bewohner**, kein Zufallsvogel des Chunks. Er wird nicht mit dem Schwarm gespawnt, sondern von `PetRegistry` verwaltet.

### 7.2 Revier und Tagesablauf (wie bei Settlern: reine Funktion der Uhr)

Weil Ambient-Tiere sonst nicht gespeichert werden und Chunks wegfallen, wird der Aufenthaltsort eines nicht geladenen Vogels **nicht simuliert, sondern berechnet**: `PetSchedule.place(record, time_of_day)`.

- **Heim:** ein echter Schlafbaum aus `bird_perches` oder ab Stufe 3 ein Dach/Laternenplatz in der Stadt (`RoofPerch`, `TownCritters`).
- **Revier:** Radius etwa 8 Tiles um das Heim, drei Lieblingsplätze (Stein, Baumstumpf, Futterstelle).
- **Tag:** Plan zwischen Futterplatz 1 → 2 → 3 und Ruhe, mit Streuung durch seinen Seed.
- **Nacht:** Heim. Gefährten schlafen in der Stadt oder auf ihrem Schlafplatz.
- Lädt ein Chunk, der seinen berechneten Ort enthält, spawnt `PetRegistry` den echten `PetCorvid` an dieser Stelle (Host, `MultiplayerSpawner`). Entlädt der Chunk, wird er abgebaut, `last_seen` wird gespeichert. **Ein Vogel in Flucht verlässt nie dauerhaft sein Revier:** nach Gefahr kehrt er zurück (Leine).

Damit ist er **jederzeit wiederzufinden**: Man geht zu seinem Revier, zur passenden Tageszeit, und er ist da. Die Karte zeigt es (9.2).

### 7.3 Schwarmverhalten

Registrierte Vögel hören weiter Schwarm-Alarme (sie sind keine Statisten), kehren aber zurück und zählen **nicht** zum 8-Vogel-Ambient-Budget. Eigene Obergrenze: höchstens 6 geladene Haustiere insgesamt. Pets sind aus `WildlifeEvents` (Jagd, Spiel) als Beute **ausgenommen**.

### 7.4 Sicherheit

- Pets sterben nicht. Gefahren (Nacht-Raid, Spinnen, Boss) scheuchen sie nur auf. Ein „verletzt“-Zustand ist **nicht** Teil der ersten Version.
- Nachts bleiben sie im Stadtlicht oder verstecken sich (Heim). Schattenwesen ignorieren Pets.

---

## 8. Gefährte (Stufe 5)

### 8.1 Annehmen und entlassen

Bei Stufe 4 wird der Vogel von selbst anhänglich, bei Stufe 5 fragt eine Geste „Soll ich mit?“ (E am Vogel, Prompt „MITNEHMEN“). Pro Spieler **ein aktiver Gefährte** (Slot). Ein zweiter Slot später über eine Fähigkeit/ein Talisman-Perk. „Freilassen“ im Buch schickt ihn zurück in sein Revier, die Bindung bleibt.

### 8.2 Befehle (neue Input-Actions über `InputManager`)

- **Pfiff** (kurz): „Komm her“ – er fliegt zu ihr, setzt sich auf die Schulter oder in die Nähe. Tastenvorschlag G, Gamepad: D-Pad runter.
- **Pfiff halten**: Wechsel *Folgen / Bleiben / Heim* (kleine Radialauswahl als Ranken-Tags). „Bleiben“ setzt ihn auf eine Stange/Baum und er wartet.
- **Fähigkeit auslösen** (Taste F? bestehende Belegung prüfen; Vorschlag: gehaltener Pfiff + Richtung): nur für aktive Gaben mit Abklingzeit, siehe 10.

### 8.3 Verhalten

- **Folgen:** Flugschleifen wie bisher (kontinuierlicher Vorwärtsflug, Bögen, Gleitphasen), Landung auf legalen Plätzen oder auf ihrer **Schulter**, wenn sie steht. Er hält Abstand 24–70 px, springt nicht durch Mauern, nutzt vorhandene Perch-/Landeprüfung.
- **Schulter:** Wenn Ellie steht (Lagerfeuer, Dialog, Angeln), landet er dort. Dafür braucht Ellies Rig einen Schulterpunkt pro Frame (wie das Schmuck-Rig, `art_hero_jewelry.py`). Fallback ohne Schulterart: er sitzt direkt neben ihr.
- **Türen, Waystones, Mine:** Er folgt durch Innenräume (Dachbalken in Hütte, Nähe der Tür), erscheint 2 s nach dem Teleport (nutzt `Interiors.use_door`, `Player.request_teleport`-Ereignis). In der Mine bleibt er in Reichweite.
- **Wasser:** fliegt über Schwimmenden. **Zwischensequenzen/Geschichte:** er verschwindet (versteckt) und kommt danach wieder.
- **Kampf:** Er hält sich zurück. Gaben (Ablenken, Warnen) greifen nach Eigenschaft (Mutig → aktiver).
- **Nacht:** Er bleibt in Stadtnähe, ist sichtbar nervös bei Raid-Omen (Warnruf).
- **Entfernung/Absturz:** Fällt der Besitzer weg (Disconnect, Tod, Szenenwechsel), geht er in sein Revier zurück.

### 8.4 Persönlichkeit im Alltag

Er reagiert auf das, was Ellie tut: dreht den Kopf zu Bäumen, die sie fällt, pickt Käfer auf, die sie ablesen kann, schaut beim Angeln zu und landet auf der Rute, hüpft bei Regen unters Dach. Das sind **Idle-Verhalten**, keine Fähigkeiten.

---

## 9. Anzeigen und Wiederfinden

### 9.1 Anzeige am Vogel (`PetTag`, Rankenstil)

Über dem Vogel (unbeleuchtet wie `InteractPrompt`): eine kleine Rindenpapier-Karte mit **Name** (PixelText), **Federchips** (fünf Pips, gefüllt = erreichte Stufe) und einem dünnen **Saft-Faden** für den Fortschritt zur nächsten Stufe. Dazu ein **Stimmungszeichen**: hungrig, satt, schläfrig, aufgeregt, ängstlich. Sichtbarkeit: dauerhaft ab Stufe 2 innerhalb von etwa 150 px, bei Blickkontakt/Zielen mit dem Cursor immer, sonst ausgeblendet. Beim Füttern wächst die Karte kurz heraus und zeigt den Zuwachs. Farben nach Designleitfaden (Gold = Bindung, Teal = Leben, Rot = Gefahr), Magenta nie (das gehört den Schattenwesen).

### 9.2 Karte (M)

`MapPets` (wie `MapWaystones`): Federsymbol pro bekanntem Vogel. Zuletzt gesehener Ort als Symbol, sonst gestricheltes **Revier** (Ring) um das Heim. Beim Überfahren: Name, Stufe, „zuletzt gesehen vor X Tagen“. Rechtsklick: „Wegmarke zum Revier“. Gefährten werden live angezeigt.

### 9.3 Erkennbarkeit in der Welt

- **Fußring** ab Stufe 2 (farbiges Pixel am Bein), ab Stufe 4 ein **Halsband/Schnur**, ab Stufe 5 ein **Anhänger**. Umsetzung als Overlay-Sheet im Layout von `corvid.png` (nur die Ring-Pixel), bildsynchron wie `ShadowEmission`/`TalismanLayer`.
- **Stimme:** der eigene Ruf (4).
- **Antwortruf:** Wer pfeift (oder in der Nähe das Buch öffnet), hört aus der Ferne seinen Ruf zurück, gerichtet (Stereo), und sieht am Bildschirmrand einen Federpfeil, solange der Vogel geladen ist.

### 9.4 Das Buch der Gefiederten (`PetBook`, Pausenmenü-Tab plus freie Taste)

Wie `RiverBook` und `FishBook`: eine Seite pro Vogel. Animiertes Mini-Porträt (Idle-Frames), Name, Art, Stufe/Bindung, **entdeckte** Eigenschaften und Vorlieben (zunächst „???“), Revier mit „Wegmarke setzen“, Statistik (Tage, Fütterungen, Geschenke) und ein **automatisches Tagebuch** („Tag 7: nahm erstmals Futter aus der Hand.“). Hier werden Gefährte ernannt/entlassen und Namen geändert. Speicherung in `PetRegistry` (Spielstand), nicht in einer eigenen Datei.

### 9.5 Futter-Tooltips

`ItemTooltip` bekommt eine Zeile „VOGELFUTTER“ mit den bereits entdeckten Reaktionen („Rabe: liebt“). Das macht Experimentieren belohnend.

---

## 10. Gaben (Fähigkeiten)

Leitlinie: **Nützlich, charmant, kein Pflichtkampfwerkzeug.** Ein Gefährte darf nie das Gefühl geben, Pflicht zu sein. Jede Gabe hat Abklingzeit, ist an Stufe/Eigenschaft/Art gebunden und standardmäßig automatisch (passiv), nur wenige sind aktiv.

| Gabe | Art | Stufe | Wirkung |
|---|---|---|---|
| **Fundnase** | Krähe (passiv) | 4 | Kreist/ruft bei reifen Beeren, Glimmkappen, Erzfelsen und Flora im Umkreis 120 px (Cooldown 45 s). Zeigt als Federglanz auf den Objekten. |
| **Beutezug** | Krähe (passiv) | 5 | Hebt liegende Drops im Umkreis 80 px auf und legt sie ihr vor die Füße (Magnet-Erweiterung, kein Diebstahl am Gegner). |
| **Glitzerfund** | Rabe (passiv) | 4 | Einmal pro Tag ein Mitbringsel (Münzen, Kiesel, selten Harz/Feder) an der Sitzstange oder im Hort. Wert klein (ca. 10–40 Kupfer-Äquivalent/Tag). |
| **Warnruf** | Rabe (passiv) | 4 | Meldet Schattenwesen schon 12–20 Tiles vor dem Raid, früher als Omen/Banner; ein Ruf mit Richtungsanzeige. |
| **Angelhinweis** | beide (passiv) | 4 | Kreist über Wasser mit hoher Aktivität. Bisher in `docs/fishing.md` als „Vogelhinweise“ offen. |
| **Ablenken** | Mutig (aktiv) | 5 | Flattert einen nahen Gegner an (Zielwechsel/Verlangsamung 1,5 s, Cooldown 30 s). Keine Schadenszahlen, kein Tod. |
| **Kundschafterflug** | Rabe (aktiv) | 5 | Hält sie die Taste, fliegt der Rabe voraus: freie Kamera (Mechanik von `FreeCam`) bis 25 Tiles, 10 s, deckt Nebel der Karte auf (`MapDiscovery.reveal_disc`). Nicht im Kampf (Gegner innerhalb 20 Tiles), bricht bei Treffer ab. Cooldown 90 s. |

Das ist bewusst das „Wow“ des Systems: Der Rabe ist ein *Auge*, die Krähe eine *Hand*.

---

## 11. Mitbringsel und der Hort

Ab Stufe 3 sammeln Vögel kleine Funde. Bei Stufe 3 legen sie es an den Rand ihres Reviers. Ab Stufe 4 haben sie einen **Hort** (Baumhöhle, Dachrinne, Sitzstange in der Stadt) als `ItemBox` (kleine Kapazität, 6 Plätze, `BoxWindow` existiert) und füllen ihn täglich nach einer Tabelle (`data/pets.json` `gifts`). Der Hort ist per Karte findbar. Gefährten legen die Funde direkt in die Hand/den Beutel.

Beispiele: blanke Kiesel, Flaschenscherben, Federn, Kupfer, ein Pilz, selten ein Harzklumpen. Selten, nur durch Treue erreichbar, ein *Glitzerstück* als Basteloption (Tooltip-Erzählung, kein Powercreep). Keine Talismane, keine Waffen.

---

## 12. Stadt und Welt

- **Sitzstange / Rabenhorst** (neues Stadtstück, `TownManager`): gibt dem Vogel ein festes Heim im Licht, zählt als Bindungsbonus (+1 BP/Tag), Geschenke landen im Hort.
- **Futterstelle:** Stadtstück mit Schale, zieht Futter aus dem Lager (`town.stock`) in kleinen Mengen, lockt wilde Krähen an und füttert registrierte Tiere (Pflege auch ohne Spieler: halbe BP).
- **Stadt-Tab:** zeigt „Haustiere“ (Name, Stufe, wo).
- **Bewohnerlinien:** Valdric, Gustav, Torben haben je 1–2 Zeilen zu Ellies Vogel (Placeholder; Dialogtexte schreibt der Dialogue-Writer, nicht hier). Gustav ärgert sich über Nägel, Torben mag den Rabenhunger nach Glühendem nicht.
- **Rissfeder-Querverweis:** Der Talisman besitzt bereits `corvid_calm` (Krähen und Raben beruhigen). Ein Träger kann Fremde schneller auf Stufe 1 heben: z. B. -30 % benötigte Annahmezeit, +5 % BP.
- **Nacht/Raid:** Registrierte Raben melden Omen früher (siehe `Warnruf`), Gefährten bleiben im Licht.

---

## 13. Spielfluss: Wann und wie man hineinkommt

- Freigeschaltet erst nach dem Prolog (`opening_over`, Stadt gegründet); ein Hinweiskärtchen (`HintCard` Fall `pet`) erscheint beim ersten Mal, dass Ellie Futter in der Hand hält und eine Krähe in 6 Tiles Nähe ist. Keine Questpflicht.
- Gefährte (Stufe 5) bleibt optional. Optional später: kleiner Quest-Faden („Der Rabe von Torben“, „Wer hat meinen Löffel gestohlen?“).
- Boss und Nacht verlangen *nie* einen Vogel.

---

## 14. Zahlen (Startwerte, zum Balancen)

| Größe | Wert |
|---|---|
| Stufenschwellen BP | 10 / 40 / 100 / 190 / 300 |
| Fütterungspunkte (Liebt/Mag/Neutral) | 12 / 7 / 3 |
| Tagesdeckel | 3 × 100 %, 3 × 50 %, danach 10 % |
| Pause pro Vogel | 20 s |
| Annahmezeit | 1 s (Freund) … 6 s (Fremd, scheu) |
| Interaktionsreichweite | 48 px (Fremd/Beäugt: 32 px) |
| Tage bis Gefährte | etwa 8–10 |
| Geladene Pets (Obergrenze) | 6 |
| Aktive Gefährten pro Spieler | 1 |
| Hort-Kapazität | 6 |
| Kundschafterflug | 25 Tiles, 10 s, Cooldown 90 s |

Ein Sim-Script wie `tools/sim_refine.py` (`tools/sim_pets.py`) prüft die Tage bis zur Stufe für Spielertypen (täglich, jeden zweiten Tag, Pausen).

---

## 15. Technische Architektur

Passend zu den Regeln des Projekts: Host entscheidet, `@rpc` mit Serverprüfung, Daten in JSON, Input nur über `InputManager`, statisch typisiert.

**Daten**
- `data/pets.json`: Stufen, BP-Kurven, Futtertabelle, Eigenschaften, Namenspools, Gaben, Hort-Tabellen, Begleiterwerte, Karten-/Tag-Werte.
- `data/wildlife.json`: pro Art ein optionaler Block `pet: {enabled, tastes, abilities, call_voice}`.
- `data/items.json`: `hotbar: true` an Futteritems; optional Feld `pet_food` für Tooltips.

**Logik**
- `PetRules` (`src/systems/pet_rules.gd`, rein): Stufe aus BP, Tagesdeckel, Reaktion, Annahmezeit, Abnahme, Gabenfreigabe.
- `PetSchedule` (rein): Position aus Uhr, Seed, Heim (wie `TownManager.walk_route`/Settler-Plan).
- `PetRegistry` (`src/pets/`, Knoten von `WorldLevel`, Gruppe `pets`): Tabelle, Host-Prüfungen `request_feed/rename/take/release/mode/ability`, `_rpc_pet_state`, Schnappschuss für Beitretende, Speichern als `"pets"` im `SaveGame`, Spawn/Despawn der Vögel (kein Doppelspawn).
- `PetCorvid` (`extends WildCorvid`, geerbte Szene): Felder `pet_id`, `mode`, `stage`, `owner_id`; überschreibt `_sense` (Furchtfaktoren nach Stufe), `_think` (Revierleine, Folgen, Anflug), Futter- und Begleiterzustände als zusätzliche `State`-Werte (FEED_WAIT, TAKE, FOLLOW, PERCH_SHOULDER, STAY). Replikation: Spawn-Eigenschaften über `MultiplayerSynchronizer`, atomare `_act`-Pakete bleiben.
- `PetFeedSpot` (Interactable-Kind am Vogel): Prompt „FÜTTERN“ nur wenn gültiges Futter in `active_stack()` und Reichweite stimmt. Er schlägt das Essen-E.
- `PetOwnerComponent` (Kind jedes Players): Gefährtenslot, Pfiff, Befehle, Gabencooldown; Teleports/Türen melden „Folge mir“.
- `PetAbilities`: Fundnase/Beutezug/Warnruf/Kundschafterflug. Hooks: `NightDirector` (Omen), `ItemDrop`/Magnet, `MapDiscovery`, `FreeCam`.

**UI**
- `PetTag`, `MapPets`, `PetBook` (Pausenmenü-Tab + Taste), `GameCursor.Look.PET`, `HintCard` Fall `pet`, `ItemTooltip` Futterzeile, Banner bei Stufen.

**Hooks in bestehendem Code (minimal):** `WildlifeEvents` schließt Pets aus; `CorvidPopulation` überspringt Pets beim Chunk-Unload und beim 8er-Budget; `StealthComponent`/`AttackComponent.noise_scale` ignorieren Pets ab Stufe 3; `Player` bekommt „Hand ausstrecken“ (Kniebeuge, anfangs `begin_pick`-Ersatz); `SaveGame` speichert `"pets"`.

**Multiplayer:** Bindung ist **pro Spieler**, Tagesdeckel pro Spieler. Das Tier ist einmalig. Ein Gefährte gehört einem Spieler (Anzeige „Gefährte von X“). Offene Frage: stabiler Spieler-Schlüssel (`player_uid`), weil `SaveGame` heute nur den lokalen Spieler speichert (Abschnitt 17).

**Tests**
- `tools/test_pets.tscn`: `PetRules`, Tagesdeckel, Schwellen, Abnahme, `PetSchedule`, Registry-Speichern/Laden, Chunk-Unload ohne Duplikate, Futterablehnung ohne Itemverlust.
- `tools/test_pets_network.tscn` (Host `-- --server`, dann Client; freier Loopback-Port): Füttern vom Client, Stufenaufstieg, Beitritt mit Pet-Snapshot, Gefährte folgt, zwei Spieler am selben Vogel.
- `tools/preview_pets.tscn` (Offline-Werkbank, `-- --capture=...`), `tools/sim_pets.py` (Zeit bis Stufe).

---

## 16. Kunst und Ton

Kunstarbeit läuft laut Projektregel über einen `gpt-6.1-terra`-Subagenten, Technik, Integration und Prüfung bleiben beim Hauptagenten.

- **Ellie:** neuer Clip „Hand ausstrecken“ (Hocke, Hand mit Futter, Halten und Hinhalten-Schleife, 8 Blickrichtungen, `tools/art_hero3d.py`-Modus, Blutmaske ggf.), Schulterpunkt-Rig für den Vogel (Schmuck-Rig-Muster).
- **Vogel:** `tools/art_pet_marks.py` – Overlay-Sheet (Fußring in 6 Farben, Halsband, Anhänger) im Layout von `corvid.png`; zusätzliche Frames: *Futter aus der Hand* (Kopf nach unten, Schnabel zur Hand, 8 Richtungen), *Schulter-Sitz* (8 Richtungen, links/rechts), *Betteln* (Flügel-Zittern). Der Rest nutzt vorhandene PECK/WATCH/PREEN/CALL-Frames.
- **UI:** Federchip-Glyphen, Revier-Ring, Federsymbol der Karte, Cursor-Glyph „PET“ (`tools/art_cursor.py`), Buchseite.
- **Ton** (`tools/audio_pets.py`, synthetische Platzhalter): Annahmeton, Stufenakkord, persönliche Rufe (Pitch-Offset je Seed), Pfiff, Antwortruf, Hort-Klimpern, Warnruf. Alles räumlich, folgt Master-/Effektlautstärke und der Ruf-Dichtegrenze.

---

## 17. Entscheidungen (geklärt)

1. **Futter:** Items direkt im Hotbar-Slot (`hotbar: true` an den Futteritems), kein Futterbeutel.
2. **Gefährten:** genau einer pro Spieler. Ein zweiter Slot ist später möglich.
3. **Tod/Verletzung:** nie. Haustiere werden nur gescheucht.
4. **Gabenstärke:** Komfort und Erkundung, keine spürbare Kampfhilfe. Ablenken bleibt kurz und ohne Schaden.
5. **Rabe und Krähe:** gleichwertig, Rabe = Auge (Kundschafter, Warnruf), Krähe = Hand (Fundnase, Beutezug).
6. **Multiplayer-Schlüssel:** zunächst Solo und Host. Client-Bindungen folgen, sobald Spieler-IDs im Spielstand existieren.
7. **Freischaltung:** nach dem Prolog (`opening_over`), mit Hinweiskarte beim ersten Futter in Vogelnähe.
8. **Umbenennen:** freie Texteingabe wie beim Teleport-Feld.
9. **Schulter:** gleich in Version 1 (Schulterpunkt-Rig nach dem Schmuck-Muster und Schulter-Frames für den Vogel gehören in P3).
10. **Tasten:** Pfiff auf G (Gamepad: D-Pad runter). Das Vogelbuch läuft nur über das Pausenmenü, keine eigene Taste.

## 18. Umsetzungsreihenfolge

| Phase | Inhalt | Ergebnis |
|---|---|---|
| **P0 Fundament** | `pets.json`, `PetRules`, `PetRegistry`, `SaveGame`, Tests | Rechenkern prüfbar, kein Gameplay |
| **P1 Füttern** | `PetFeedSpot`, Annahme-Logik, Reaktionen mit vorhandenen Frames, Wurf-Futter, `PetTag`, `HintCard` | Man kann wilde Krähen füttern und Fortschritt sehen |
| **P2 Fest in der Welt** | Registrierung ab Stufe 2, `PetSchedule`, Revier, Spawn/Despawn, Karte, Buch, Namen, Fußring | Der Vogel bleibt, ist wiederzufinden |
| **P3 Gefährte** | `PetOwnerComponent`, Pfiff, Folgen, Türen/Waystones, Nacht, Schulter | Er begleitet |
| **P4 Gaben und Stadt** | Gaben, Hort, Kundschafterflug, Sitzstange, Futterstelle, Bewohnerzeilen | Sinnvoller Nutzen |
| **P5 Politur** | Ton, Cursor, Zeremonien, Zahlen balancieren, weitere Arten (Eule, Wiedehopf) | Feinschliff |

Pro Phase: eigenes Testszenario, vorher Konzept-Freigabe. Nach P2 wird dieses Dokument durch einen Abschnitt in `CLAUDE.md` ergänzt.

## 18. Schwierigkeit: an Krähe und Rabe kommt man nicht einfach heran

- Ein Vogel zeigt nur dann Interesse, wenn alle Bedingungen zugleich gelten: passendes Futter im gewählten Hotbar-Slot, **Schleichen**, **Stillstehen** (< 9 px/s), kein Sprint/Schlag, innerhalb der **Lockweite** (Krähe 56 px, Rabe 50 px, knapp außerhalb des normalen Fluchtradius beim Schleichen), Abklingzeit und Tagessättigung ok. Das Interesse (`PetBehavior.interest`, pro Spielerin, unsichtbar) wächst langsam und fällt schnell.
- Ab 0,35 Interesse bleibt der Vogel trotz Nähe ruhig, bei 1,0 hüpft er heran (Abstand ~15 px), ab 0,7 bietet er sich an (Spähen, Kopfdrehen); dann erscheint „E FÜTTERN“. Wer rennt, schlägt oder vom Vogel wegläuft, verliert alles.
- **Rissfeder (Mornath):** `corvid_calm` weitet die Lockweite um bis zu +120 % und beschleunigt das Interesse um bis zu +150 % – der Schlüssel zum ersten Kontakt. Mit wachsender Bindung wird der Vogel zutraulicher (`stage_range`).
- Alle Grafiken (Fütter-Clip, Futter in der Hand, Federn/Ring-Effekt) sind selbst gemacht: gleiche Ellipsoid-Pipeline und Pixelregeln wie der Rest.

## 19. Drei Schritte

1. **Heranpirschen, Füttern, Bindung** (gebaut): `data/pets.json`, `PetRules`, `PetRegistry` (Knoten `PetRegistry` im Level, Save-Schlüssel `pets`), `PetBehavior` (Locken, Hüpfen, Anbieten, Nehmen), `PetFeedSpot` (E), Clip `player_feed.png` (`py -3 tools/art_hero3d.py feedonly`), `FeedFx`, `PetBondFx`, Sounds `py -3 tools/audio_pets.py`. Test `tools/test_pets.tscn` (21 Checks) + `test_corvids.tscn`. Vogel-Identität = `pet_key` (Schwarm-ID + Platz), reicht bis Schritt 2.
2. **Fest in der Welt** (gebaut, Stand 2026-11-10): ab Stufe 2 (`register.stage`) legt der Host beim Füttern einen Eintrag an (`PetRegistry.ensure_record`: Name aus dem Pool der Art, Ringfarbe, Heim = wo der Vogel steht). Der Vogel verlässt seinen Schwarm: `CorvidPopulation` überspringt seinen Schwarmplatz (gleiche Zufallszüge, der Rest des Schwarms bleibt wie er war), das Budget der 8 Wildvögel zählt ihn nicht mehr, und `PetRegistry._maintain_pets` (Host, jede Sekunde) setzt ihn an seinen Platz laut `PetSchedule` (reine Funktion: nachts Heim, tags drei Lieblingsplätze im Revier, Radius 36-104 px), solange dessen Chunk geladen ist (höchstens 6 gleichzeitig). Seine Spaziergänge lehnen sich ans Revier (`WildCorvid.territory`), ein weit abgekommener Vogel steht ungesehen (kein Spieler im Umkreis von 420 px) wieder im Revier; entlädt der Chunk, wird er abgebaut und sein letzter Ort gespeichert (`seen`, wird alle 20 s an die Clients geschickt). `PetTag` (Name, fünf Federn, Fortschrittsfaden, "+N" nach dem Füttern; in 150 px Nähe, unter der Maus, nach dem Füttern), Fußring (`py -3 tools/art_pet_marks.py`: Overlay `assets/wildlife/pet_marks.png` im Layout von `corvid.png`, nur die Ring-Pixel auf dem echten Bein jedes Frames, Farbe = Ringfarbe), Karte (`MapPets`: Feder in Ringfarbe am letzten Ort, gestrichelter Revierring, Karte mit Name/Stufe/zuletzt gesehen unter der Maus), Buch (Pausenmenü-Tab **VÖGEL**: Liste, Seite mit Art/Stufe/Bindung/Ring/Ort, Umbenennen mit Textfeld, Host säubert und prüft die Stufe), Abnahme (`decay`: nach 3 Tagen ohne Kontakt -3 BP am Tag, nie unter die Stufe davor, nie unter Stufe 2 bei einem registrierten Vogel). Test `tools/test_pets.tscn` (48 Checks). **Noch nicht:** Futter am Boden (braucht den Werfer am `ItemDrop`), Stimmungszeichen am Tag, Eigenschaften/Vorlieben im Buch als "???" entdecken, Wegmarke zum Revier, Dach/Laterne in der Stadt als Heim, Stufen-Szene und Banner, Hinweiskarte.
3. **Gefährte:** Pfiff (G), Folgen, Schulter-Rig und -Art, Fähigkeiten, Hort, Stadtteile, Dialogzeilen.

Noch offen aus Schritt 1: ein Hinweis-Karteikärtchen (`HintCard`).


### Schritt 3 gebaut: Gefährte

Buch (VÖGEL) bei Stufe GEFÄHRTE: MITNEHMEN / ENTLASSEN / MODUS WECHSELN. Genau ein Gefährte pro Spieler. G antippen ruft, G halten (0,6 s) wechselt FOLGEN / BLEIBEN / HEIM. Folgt fliegend, sitzt nach 2,6 s Stillstand auf der Schulter (vorhandene ROOST-Frames), springt bei Sprint/Schwung ab, verschwindet in Räumen und der Mine. Gaben: Krähe FUNDNASE, Rabe WARNRUF (nur Hinweise, kein Kampf). Test `tools/test_pets.tscn` (63 Checks). Danach gebaut: E am Vogel (MITNEHMEN / HORT), Hort (12 Plätze, Mitbringsel/Glitzerfund alle 5-9 Min, max. 4 am Tag), Kundschafterflug des Raben (G antippen, 90 s), HEIM auf Stadt-Sitzstangen, Pfiff-Ton und Noten. Test `tools/test_pets.tscn` (73 Checks). Offen: Körperanimation für Pfiff/Schulter (keine neuen Sheets), Snapshot der Gefährtentabelle für Spät-Joiner.
