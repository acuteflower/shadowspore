# Talismane (Schmuck): Ketten, Ohrringe, Armbänder

Stand 2026-11-09. **Gebaut: Schritte 1 bis 4** (Daten und Regeln, Gattungsregel im Inventar, Wirkung, Icons, Tooltip mit Vergleich, Runen der leeren Plätze, Entwicklerknöpfe TALISMANE ANLEGEN / ABLEGEN; Test `tools/test_talismans.tscn`, Kartenvorschau `tools/preview_talisman_card.tscn`, Icons `py -3 tools/art_talismans.py`). **Danach gebaut: Schritte 5 bis 7** (Ellie-Optik über `data/hero_jewelry.json`, `TalismanArt` / `TalismanLayer`, Armband am Handgelenk, Inventarpuppe, Klänge, Funkeln beim Schlucken; Vorschau `tools/preview_talismans.tscn`, Bild `docs/img/talisman_worn.png`; Szenenbögen und Dialogbilder bleiben ohne Schmuck). **Offen: Schritt 8** (Beschaffung und Zahlen). Anders als beschrieben: die Sichtbarkeit kommt nicht aus dem Tiefenpuffer, sondern aus Blickrichtungs-Werten (Ohren immer über dem Haar gezeichnet, sonst wären sie unter den Haarsträhnen unsichtbar). Die Beschreibung unten ist das Konzept; was beim Bauen anders kam: ein zweites Stück, wenn nur ein Platz offen ist, tauscht mit dem ersten (wie bei allen Ausrüstungsplätzen); `StealthComponent.alarm_scale()` gilt nur beim ersten Bemerken (Spinne: `_find_target`; Lauscher und Brecher: Sicht und Gehör, solange sie sie nicht schon verfolgen), nicht für die Verlustreichweite. Dieses Konzept hängt an dem, was es schon gibt: drei Talisman-Plätze (`talisman_1..3`, öffnen mit den Stufen 5 / 15 / 25, siehe `docs/level_fortschritt_konzept.md`), das Slot-Gerüst in `InventoryComponent`, `HealthComponent.armor`, `StealthComponent`, `HeavyRules` und die Rig-Punkte des Heldinnen-Renderers. Es gibt noch **keinen einzigen Talisman-Gegenstand** und keine Wirkung.

## 1. Kurzfassung

- Talismane sind **Schmuckstücke**, die man **sieht**: Kette am Hals, Ohrringe an den Ohren, Armband am Handgelenk der Schwerthand. Silber, Gold, Leerenstahl, mit oder ohne Kristall, je nach Seltenheit und Gegenstand verschieden.
- **Drei Gattungen, je nur eine anlegbar:** Kette = **Körper** (Verteidigung), Ohrringe = **Leere und Magie** (Wahrnehmung, Schutz vor der Leere, später Zauber), Armband = **Angriff**. Ein zweites Armband ersetzt das erste, es gibt nie zwei Gleiche zugleich.
- Die ersten drei: **Schlichte Silberkette** (gewöhnlich: +12 Leben, +2 Rüstung), **Wuchtreif** (selten: +8 % Schaden, +15 % Wuchtschlag-Schaden, +25 % Aufladetempo), **Schweigtropfen** (legendär: Alarmreichweite der Schattenwesen −50 %, −25 % jeder Schaden).
- **Technik in einem Satz:** Bonuswerte sind Daten (`data/talismans.json` plus Eintrag in `items.json`), eine reine Regelklasse `TalismanRules` rechnet sie zusammen, ein kleiner `TalismanComponent` am Spieler hängt sie an Leben, Rüstung, Schaden und Gegner-Wahrnehmung. Das **Aussehen** kommt nicht in die Körperbilder gebacken, sondern wird aus Rig-Punkten gezeichnet (Abschnitt 5), sonst müsste jeder Schmuck mit jeder Kombination alle 20 Bildbögen neu rendern.

## 2. Was es schon gibt (und was fehlt)

| Baustein | Stand | Folge für die Talismane |
|---|---|---|
| Plätze `talisman_1..3` | vorhanden, `slot_open()` sperrt sie nach Stufe (5 / 15 / 25), `InventoryWindow` zeigt versiegelte Knospen | bleiben **frei** (jede Gattung in jeden Platz), die Einzigartigkeit regelt `_equip` |
| `Items.fits_slot` | prüft `slot == accepts` | Talisman-Items haben `slot: "talisman"`, dazu `jewelry` (Gattung) |
| `HealthComponent.armor` | kommt aus `ProgressComponent.apply_stats`; Schaden × `80/(80+armor)` | Kette addiert Rüstung dort; neu: `absorb` (Ohrringe) |
| `StealthComponent.detection_multiplier()` | Spinne, Lauscher und Brecher fragen ihn schon für die **Sichtweite** (Schleichen = 0,5) | die Ohrringe hängen sich hier an; für das **Gehör** (`hearing_*`) fehlt der Faktor noch (drei Stellen) |
| `HeavyRules` / `AttackComponent` | Wuchtschlag: Aufladung `_charge_time += delta`, Schaden `damage_min .. damage_full` | Armband: ein Faktor auf den Schaden, einer auf die Aufladezeit |
| Veredeln (`r`, `rp` am Stapel) | läuft | Schmuck bleibt vorerst **unverfeinert**; die Stapel tragen nichts Neues |
| Heldinnen-Renderer | `m.rig[...]` projiziert Punkte pro Bild (so entsteht `eat_mouth`) | Ohr-, Hals- und Brustpunkte kommen auf demselben Weg |
| Ellie trägt schon | **Choker mit kleinem violettem Kristall** (im Körperbild gebacken) und eine **goldene Haarnadel** | die Kette hängt **unter** dem Choker; nichts davon wird ersetzt |

## 3. Die drei Gattungen

| Gattung (`jewelry`) | Bereich | Wirkt auf | Stat-Schlüssel (Beispiele) |
|---|---|---|---|
| `necklace` Kette | **Körper**, defensiv | Leben, Rüstung, Überheilung, Regeneration, Statuswiderstand (Brand), Rückstoßwiderstand | `health`, `armor`, `overheal`, `regen`, `resist_burn`, `knock_resist` |
| `earrings` Ohrringe | **Leere und Magie** | wie Schattenwesen sie wahrnehmen und was die Leere ihr tut; später Zauber, Blinzeln | `alarm`, `absorb`, später `blink_cooldown`, `spell_*` |
| `bracelet` Armband | **Angriff**, offensiv | Schaden, Wuchtschlag, Tempo, Reichweite, Rückstoß | `damage`, `heavy_damage`, `charge_speed`, `attack_speed`, `reach`, `knockback` |

Die ersten Ohrringe (Alarmreichweite, Schaden schlucken) sind **Leerenschutz**, also genau dieser Bereich: die Leere geht an ihr vorbei. Die eigentliche Magie (Zauber, Blinzeln) ist Platzhalter und braucht nur einen Eintrag im Stat-Katalog, wenn es so weit ist.

### 3a. Regel "nie zweimal dieselbe Gattung"

- Die Plätze bleiben **frei** (nicht Hals/Ohr/Hand fest), denn sie öffnen einzeln bei 5 / 15 / 25. Bei Stufe 5 wählt man, was der erste Platz trägt; bei Stufe 25 trägt man zwangsläufig je eines. **Die Entscheidung liegt darum zwischen Einzelstücken einer Gattung** (Abschnitt 8: mindestens drei Kandidaten je Gattung bis Stufe 15).
- `TalismanRules.conflict(equipment, slot, stack) -> String` gibt den Platz zurück, in dem schon dieselbe Gattung steckt (sonst `""`). Verhalten:
  - **Rechtsklick / Shift-Klick / Zahlentaste** (automatisch): das neue Stück **tauscht mit dem gleichartigen**, egal ob ein anderer Platz frei wäre (`_slot_for` nimmt zuerst diesen Platz). Das alte wandert in den Rucksack (oder auf den Cursor).
  - **Klick auf einen bestimmten anderen Platz** (Cursorstapel): **abgelehnt**, der Platz wackelt, ein Hinweis erscheint ("SCHON EIN ARMBAND ANGELEGT"). Kein stilles Tauschen an der falschen Stelle.
- Gleiches Stück zweimal im Beutel ist erlaubt, anlegen kann man nur eines.

## 4. Die ersten drei Talismane (Platzhaltertexte)

Alle Zahlen stehen später nur in `data/items.json` (`bonus`) und `data/talismans.json` (Katalog und Grenzen).

### 4a. Schlichte Silberkette (gewöhnlich, Kette)

| | |
|---|---|
| Wirkung | **+12 maximales Leben, +2 Rüstung** |
| Aussehen | feine Silberkette, die zwei Glieder unter dem Choker an den Seiten ansetzt und auf der Brust in einen kleinen, glatten Silbertropfen ausläuft; **kein Stein** (gewöhnlich) |
| Text | "Eine einfache Kette. Sie hat niemanden beschützt, der sie nicht brauchte." |

Maßstab: +12 Leben sind vier Stufen (jede Stufe gibt 3), bei Stufe 5 (120 Leben) rund 10 %. Rüstung 2 heißt Schaden × 80/82, also **−2,4 %** (die Stufen geben bis Stufe 30 insgesamt 5 Rüstung). Zusammen "etwas Leben und Verteidigung".

### 4b. Wuchtreif (selten, Armband)

| | |
|---|---|
| Wirkung | **+8 % Schaden** (alle Waffentreffer), **+15 % Schaden des Wuchtschlags**, **+25 % Aufladetempo** des Wuchtschlags |
| Aussehen | offener Goldreif mit leicht geschwungenen Enden, in der Mitte ein facettierter **blauer Kristall** (Seltenheitsfarbe `5aa8ff`) mit einem kleinen Glanzpunkt |
| Text | "Ein Reif für Hände, die ausholen wollen." |

Maßstab: Wuchtschlag voll aufgeladen = Waffenschaden × 3,4; mit dem Reif × 3,4 × 1,08 × 1,15 = **× 4,22** (+24 %). Aufladung: Mindestladung 0,35 s → **0,28 s**, volle Ladung 1,0 s → **0,8 s**. Die **Haltezeit** bei voller Ladung (`hold_extra`, kostet Ausdauer) bleibt in echten Sekunden: das Tempo beschleunigt nur den Weg zur vollen Ladung, es verkürzt nicht, wie lange man halten darf.

### 4c. Schweigtropfen (legendär, Ohrringe)

| | |
|---|---|
| Wirkung | **Alarmreichweite der Schattenwesen −50 %**, **−25 % jeder Schaden** (nach der Rüstung) |
| Aussehen | geschwärzter **Leerenstahl** (`040208` .. `261a4a`, kalter Violettrand wie das Fleisch der Wesen, aber *ihr* Material), ein Haken am Ohr, daran ein langer Tropfen aus violettem Kristall mit einem kalten weißen Kern; der Tropfen **pulst** langsam im Takt des Leerenherzschlags (`VoidGlow.beat`), leuchtet nachts ein wenig (unlit-Pixel) |
| Text | "Du hörst die Leere nicht mehr. Sie dich auch nicht." |

**Magenta ist die Farbe der Schattenwesen** (Augen), darum haben die Ohrringe *Violett und Weiß*: Leerenmaterial, aber unverkennbar Schmuck und nicht Gegner.

**Alarmreichweite** heißt: ein Faktor (0,5) auf alles, womit ein Schattenwesen sie bemerkt: `sight_range` (Spinne, Lauscher, Brecher), `hearing_walk / sprint / sneak / attack` (Lauscher, Brecher), `personal_range` bleibt (Nahbereich). Er **multipliziert mit dem Schleichen** (0,5 × 0,5 = 0,25): ein Lauscher hört sie dann beim Schleichen erst auf rund 24 px statt 48, beim Gehen auf 90 statt 180, beim Rennen auf 128 statt 255. Wer schon **verfolgt** wird, bleibt verfolgt (wie beim Schleichen: der Faktor greift nur beim ersten Bemerken). Nicht betroffen: **Tiere** (Kaninchen und Krähen fliehen wie immer) und der **Köder der Nacht** (`NightDirector`-Lärm von Rennen, Hieben und Bauen): die Ohrringe machen sie im Feld unauffällig, aber den Stützpunkt nicht unsichtbar, sonst wäre jeder Überfall wegzuschmuggeln. Sieht man das anders, ist es ein Wert in `data/night.json` (siehe Entscheidungen).

**Schaden schlucken:** `HealthComponent.absorb` (0..0,5): Schaden × Rüstungsfaktor × (1 − absorb), danach rechnet die Überheilung wie bisher. Gilt für Treffer (`take_damage`) und Zeitschaden (`take_tick`, Brand), nicht für Erzählmomente (`take_survivable`, `kill`). Mit 3 Rüstung (Stufe 15) trifft dann **0,964 × 0,75 = 72 %**: gut ein Drittel mehr Leben, das ist der Preis einer legendären Seltenheit, die erst spät zu haben ist.

## 5. Aussehen an Ellie

### 5a. Das Problem und die Lösung

Ellies Körper steckt in rund 20 Bildbögen (Gehen, Schlag, Wuchtschlag, Pflücken, Essen, Ziehen, Berühren, Angeln, Bereitschaft, Sitzen, Rasten, Tragen, Szenen ...), jeder wird in Minuten gerendert, dazu je ein Blutbild. Schmuck in den Körper zu backen hieße: jede Kombination (3 Gattungen × viele Stücke) × alle Bögen. Unmöglich.

**Darum werden die Teile am Körper "aufgehängt":** `tools/art_hero3d.py` bekommt zusätzliche Rig-Punkte pro Bild (so wie `mouth`): linkes und rechtes **Ohr**, linke und rechte **Choker-Seite**, **Brustpunkt** (wo der Anhänger hängt), dazu je Punkt ein **Sichtbarkeitsbit** (Tiefenpuffer des Renderers: liegt der Punkt hinter einer Fläche, zum Beispiel das Ohr hinter dem Haar, ist es verdeckt). Das Spiel zeichnet die Stücke in einem Kindknoten des Sprites (`TalismanLayer`) pro Bild an diese Punkte. Ein neues Schmuckstück ist dann **ein paar Handvoll Pixel Kunst und ein Datensatz**, kein Neurendern des Körpers.

### 5b. Was wo sitzt

| Gattung | Sitz | Zeichnung |
|---|---|---|
| Kette | unter dem Choker: Kettenlinie von Choker-Seite links über den Brustpunkt zur Seite rechts (ein durchhängender Bogen, 1 px Kette mit 1 px Schatten), **Anhänger** am Brustpunkt | Anhänger je nach Blickrichtung: von vorn (S, SE, SW) das Vollbild, von der Seite (E, W) schmal, von hinten (N, NE, NW) **unsichtbar**, nur ein Rest Kette im Nacken, wenn nicht vom Haar verdeckt |
| Ohrringe | an beiden Ohren | von vorn beide, von der Seite nur das nähere, von hinten höchstens ein Funken zwischen den Haaren (Sichtbarkeitsbit); Haken 1 px, Tropfen 1-3 px, hängt 2-4 px |
| Armband | **rechtes Handgelenk** (die Schwertseite): der Arm wird ohnehin von `AttackComponent._draw_arm` gezeichnet (Ärmel, dunkler Armschutz, Handschuh), dort gehört ein 2 px breites Band mit Stein-Pixel auf den Armschutz kurz vor dem Handschuh | folgt der Hand genau, auch im Schwung und beim Wuchtschlag; kein Rig-Punkt nötig. Die **linke** Hand steckt im Körperbild und bekommt keinen Reif (es gibt nur ein Armband) |

Alle Teile folgen dem Laufwippen und den Posen (die Punkte sind pro Bild exportiert) und werden wie der Körper vom **Tageslicht getönt**. Nur die *Leuchtpixel* (`<id>_glow.png`, dieselbe Konvention wie bei Bäumen, Felsen, Waffen) sind **unlit** und nachts heller (`DayNight` / `night_lights`). **Ellie trägt kein Licht**: es gibt keine `NightLight`, nur das Eigenleuchten der Steine. Das Blut-/Wundmuster des Körpers berührt den Schmuck nicht.

**Welche Bögen zuerst:** Gehen/Rennen/Schleichen/Stehen (Hauptbogen), Schlag, Wuchtschlag, Pflücken/Essen/Ziehen/Berühren, Angeln, Bereitschaft. Das ist alles, was die Spielerin steuert. **Szenen** (Aufwachen, Auftauchen, Stolpern, Ohnmacht, Schrank, Tragen) bekommen vorerst **keinen** Schmuck: die Ebene versteckt sich dort (zu dem Zeitpunkt der Geschichte hat sie ohnehin keinen). **Sitzen/Rasten am Feuer** sind spielergesteuert und kommen in einer zweiten Runde dazu.

Dass der Schmuck klein ausfällt, ist kein Mangel: bei 48 × 56 px sind Ohrringe 2-4 Pixel, die Kette eine 1-px-Linie. **Der Eindruck entsteht durch Glanz, Farbe und die Seltenheit**, nicht durch Details. Wo man den Schmuck groß sieht (die Puppe im Inventar läuft mit dem 2×-Ruhebild, die Dialogbilder sind gemalt und bekommen **vorerst keinen** Schmuck), liefert die Ebene ihn ohne Zutun, solange das Ruhebild die Rig-Punkte hat.

### 5c. Seltenheit sieht man

| Seltenheit | Metall | Stein | Zusatz |
|---|---|---|---|
| gewöhnlich | Silber oder Messing, schlicht | keiner | nichts |
| ungewöhnlich | Silber / Gold | ein kleiner, glatter Stein in der Rohfarbe | ein Glanzpixel (selten, Tageslicht) |
| selten | Gold oder Silber mit Zierkante | **facettierter Kristall** in `5aa8ff` oder Familienfarbe | Glanz, der alle paar Sekunden über den Stein läuft |
| episch | Filigran, mehrere Fassungen | größerer Kristall in `b47aff` | schwach nachtleuchtend |
| legendär | **eigenes Material** (Leerenstahl, Mondgold ...), einzigartige Form | Kristall mit Kern | pulsiert, leuchtet nachts, kleine Partikel |

Ein Stein je **Verzauberungsplatz** (`enchant_slots` steht in den Items schon): später lassen sich Kristalle einsetzen, heute zeigt die Zahl der Steine im Bild nur diese Zahl.

### 5d. Wo die Kunst entsteht

Ein Skript `py -3 tools/art_talismans.py [preview.png]` (der Ellipsoid-Renderer und die Schattierungsregel von `art_weapons.py`, ein Satz Geometrie pro Stück) schreibt für jeden Eintrag: **Icon 16 × 16** (Regeln von `check_icon`: Rand 1 px, ein zusammenhängendes Stück, Kontur `1b1a2e`, Licht von links oben, Schmuck hängt aufrecht), die **getragenen Teile** (Anhänger vorn/seitlich, Ohrring vorn/seitlich) und `_glow`-Bilder. Armbänder sind **Daten** (`look`: Metallrampe, Breite, Stein-Farbe, Glanz), weil sie auf der Armlinie programmatisch sitzen. Die Kunst baue ich selbst (kein Unterauftrag, wie vereinbart).

Neue Klänge `py -3 tools/audio_talisman.py` (Platzhalter): Anlegen als heller Metallklang je Material (Silber hoch, Gold warm, Leerenstahl dumpf mit Brummen), Ablegen leiser, **Schlucken** (Ohrringe, wenn Schaden absorbiert wird: ein tiefer, kurzer Glockenton mit Ring), Armband beim Wuchtschlag-Loslassen ein feines Klirren.

## 6. Daten und Regeln

**`data/talismans.json`** (Katalog, ein Ort für Anzeige und Grenzen):

```json
{
  "types": {
    "necklace": {"name": "Kette",    "domain": "KÖRPER",  "color": "6fe0c4", "glyph": "..."},
    "earrings": {"name": "Ohrringe", "domain": "LEERE",   "color": "b47aff", "glyph": "..."},
    "bracelet": {"name": "Armband",  "domain": "ANGRIFF", "color": "ffb347", "glyph": "..."}
  },
  "stats": {
    "health":       {"label": "LEBEN",           "unit": "flat",    "min": 0, "max": 60},
    "armor":        {"label": "RÜSTUNG",         "unit": "flat",    "min": 0, "max": 12},
    "damage":       {"label": "SCHADEN",         "unit": "percent", "min": 0, "max": 0.5},
    "heavy_damage": {"label": "WUCHTSCHLAG",     "unit": "percent", "min": 0, "max": 0.6},
    "charge_speed": {"label": "AUFLADETEMPO",    "unit": "percent", "min": 0, "max": 0.6},
    "alarm":        {"label": "ALARMREICHWEITE", "unit": "percent", "min": -0.75, "max": 0.5},
    "absorb":       {"label": "SCHADEN GESCHLUCKT", "unit": "percent", "min": 0, "max": 0.5}
  }
}
```

**`data/items.json`** (Beispiel):

```json
"wuchtreif": {
  "name": "Wuchtreif", "kind": "talisman", "slot": "talisman", "jewelry": "bracelet",
  "rarity": "rare", "enchant_slots": 1, "max_stack": 1, "hotbar": false,
  "icon": "res://assets/items/wuchtreif.png",
  "bonus": {"damage": 0.08, "heavy_damage": 0.15, "charge_speed": 0.25},
  "look": {"metal": "gold", "stone": "5aa8ff", "stones": 1, "glint": true},
  "description": "..."
}
```

**`TalismanRules`** (`src/systems/talisman_rules.gd`, rein, ohne Knoten, wie `RefineRules` / `HeavyRules`):

- `type_of(stack)`, `bonus_of(stack)`;
- `conflict(equipment, slot, stack)`: Platz mit gleicher Gattung (Abschnitt 3a);
- `combine(stacks) -> Dictionary`: **addiert** alles außer `alarm`, das als Faktor **multipliziert** wird (0,5 × 0,8 = 0,4), jeweils auf die Grenzen aus dem Katalog geklemmt (Alarm höchstens −75 %, Schlucken höchstens 50 %): Sicherung gegen spätere Stapelung, auch wenn heute jede Gattung nur einmal vorkommt;
- `damage_factor(bonus, heavy)`, `charge_rate(bonus)`, `alarm_scale(bonus)`: die Zahlen, die die Verbraucher brauchen.

**`TalismanComponent`** (`src/components/talisman_component.gd`, Kind jedes Spielers, in `_ready` angelegt wie die anderen):

- Host: rechnet bei jeder Änderung von `inventory.equipment` neu und ruft die Verbraucher auf; das ist die **Wahrheit für den Kampf**.
- Alle Peers sehen die getragenen Stücke über eine synchronisierte kurze Liste (`worn`: drei Item-IDs, im selben Weg wie `held_weapon` / `held_refine`) und rechnen **dieselbe** reine `combine`-Funktion daraus: das ist nur für Darstellung, Lebensleiste und Aufladung der Besitzerin. Es braucht **keinen eigenen Bonus-RPC**, nur diese Liste.
- Verbraucher: `ProgressComponent.apply_stats` addiert `health` / `armor` auf die Stufenwerte; `AttackComponent` nimmt den Schaden-Faktor in `_hit_scan` (neben `Items.stat`) und den Aufladefaktor (Abschnitt 4b); die drei Gegner fragen `player.stealth.alarm_scale()` beim Hören und Sehen; `HealthComponent.take_damage` / `take_tick` den `absorb`.

**Zwei Fallen**, die das Konzept gleich festhält:

1. **Wechsel-Heilung:** `apply_stats` heilt die gewonnene Höchstzahl sofort, wenn jemand voll war. Mit einer Kette wäre "Ablegen / Anlegen" ein kostenloser Heiltrick (100 → 112 → 100 → 112). **Talisman-Leben wird nie sofort geheilt** und beim Ablegen auf die neue Obergrenze geklemmt (heute klemmt `apply_stats` nicht). Test: Anlegen/Ablegen in Schleife darf nie mehr Leben bringen.
2. **Aufladung und Host:** `HeavyRules.host_charge(claimed, seen, cfg)` deckelt die gemeldete Ladezeit auf die Zeit, die der Host selbst gesehen hat (+0,15 s). Mit Tempo 1,25 meldet die Besitzerin 25 % mehr: der Host muss **mit demselben Faktor** rechnen, sonst wird der Reif zu Hause schneller als im Netz.

## 7. Anzeige und Bedienung

- **Tooltip** (`ItemTooltip`): Untertitel "Selten Armband · ANGRIFF" mit Gattungsfarbe, darunter die Bonuszeilen "+8 % SCHADEN", "+15 % WUCHTSCHLAG", "+25 % AUFLADETEMPO" in der Seltenheitsfarbe (keine Waffen-Balken). Ist schon **eine Gattung getragen**, steht darunter der **Vergleich** mit dem getragenen Stück (grün besser, rot schlechter je Zeile) und die Zeile "Rechtsklick: ersetzt Wuchtreif".
- **Plätze:** ein leerer Talisman-Platz zeigt die drei Gattungen als schwache Runenzeichen, aber **nur die noch nicht getragenen**: man sieht auf einen Blick, was fehlt. Beim Anlegen funkelt der Körperteil (Hals, Ohr, Handgelenk) einmal. Das Siegel für noch gesperrte Plätze (Knospe mit der Stufe) bleibt.
- **Entwickler-Reiter:** Knöpfe "TALISMANE ANLEGEN" (die drei ersten) und "TALISMANE ABLEGEN", im Muster von WAFFE +N / STARKES SCHWERT.
- **Schmuckfeedback im Spiel:** Ohrringe flackern kurz, wenn sie Schaden schlucken (Ring, Klang), und **summen leise stärker, je näher ein Schattenwesen sie gerade untersucht** (liest den Zustand "bemerkt" der Gegner, keine neue Spielmechanik, nur eine Anzeige; das ist ein Vorschlag aus 9).

## 8. Beschaffung und Zukunft der Gattungen

Damit die Regel "eine je Gattung" eine **Entscheidung** erzeugt und nicht nur eine Einschränkung, braucht jede Gattung bis etwa Stufe 15 mindestens drei Kandidaten mit **verschiedenem Charakter**, nicht nur größeren Zahlen. Vorschläge (nur Namen, nichts davon gebaut):

| Gattung | gewöhnlich / ungewöhnlich | selten | episch / legendär |
|---|---|---|---|
| Kette (Körper) | **Silberkette** (Leben + Rüstung) | **Wurzelkette** (Leben kehrt außerhalb des Kampfes langsam zurück, türkise Perle) | **Glutherz** (Brandwiderstand, größere Überheilung), legendär offen |
| Ohrringe (Leere) | **Lauschperlen** (kleiner Alarmabzug, Rennen leiser) | **Blinzelsplitter** (Blinzeln lädt schneller, später) | **Schweigtropfen** (legendär, Abschnitt 4c) |
| Armband (Angriff) | **Messingreif** (+4 % Schaden) | **Wuchtreif** (Abschnitt 4b) | **Reif des letzten Atems** (mehr Schaden mit wenig Leben), **Sturmspange** (Tempo statt Wucht) |

**Wo sie herkommen** (Vorschläge): Silberkette in Truhen der Mine (Zone 1) und beim Händler, **Wuchtreif vom Leerenbrecher** (der Wuchtschlag ist die Antwort auf seine Frontpanzerung, dazu passt sein Reif, 5-8 %), **Schweigtropfen von Mornath** (erster Sieg sicher, danach selten). Später ein **Goldschmied** (Siedler wie Gustav und Torben): reinigen, Kristalle fassen (`enchant_slots`), gewöhnliche Stücke herstellen; **Veredeln** nach `refine.json` ist für Schmuck nicht vorgesehen.

## 9. Eigene Ideen (nichts davon ist beschlossen)

1. **Resonanz / Sets** (später): trägt sie Kette, Ohrringe und Armband derselben **Familie** (Silber, Gold, Leere), erwacht ein kleiner Zusatz und die drei Stücke glänzen im Gleichtakt. Gibt der Regel "je Gattung nur eines" ein Ziel. Braucht mindestens zwei Familien, die ersten drei sind absichtlich gemischt.
2. **Vierte Gattung Ring (Alltag)** (später, nur wenn gewollt): Angeln, Ernten, Kochen, Bauen. Brächte einen vierten Platz (zum Beispiel mit Stufe 30, "VOLLENDUNG" gibt heute keinen). Bis dahin **keine** Änderung an den Plätzen.
3. **Preis der Legenden:** ein kleiner Nachteil, der die Stärke erdet (Schweigtropfen: −15 % Heilung, "die Leere nimmt, was sie schluckt"). Standard ist **keiner**.
4. **Alarm-Anzeige durch die Ohrringe** (Abschnitt 7): der Schmuck als Lesehilfe, wie nah eine Gefahr ist, ohne neue Oberfläche.
5. **Fassungen:** die Steine im Bild folgen `enchant_slots`; später lassen sich Kristalle einsetzen und tauschen, der Stein im Bild ändert die Farbe.
6. **Anlaufen** (nur Optik): Silber läuft nachts unter der Leere dunkler an, ein Lappen oder der Goldschmied macht es wieder blank. Reine Zierde, kein Wert.

## 10. Bauplan

Schritte 1 bis 4 sind **fertig spielbar ohne Schmuckbilder** (Wirkung, Bedienung, Anzeige mit Icons). 5 bis 7 sind die Kunst.

1. **Regeln und Daten:** `data/talismans.json`, die drei Items (mit vorläufigen Icons), `TalismanRules`, Tests (Gattung, `conflict`, `combine`, Grenzen).
2. **Inventar:** `_equip`, `_slot_for`, `_accepts`, `_click` prüfen die Gattung, Ablehnung mit Hinweis; Speichern/Laden ändert sich nicht (Ausrüstung wird als `id` gespeichert). Test: Tauschen, Ablehnen, volle Tasche, gesperrte Plätze.
3. **Wirkung:** `TalismanComponent`, `HealthComponent.absorb`, `ProgressComponent.apply_stats` (mit Klemmen), `AttackComponent` (Schaden-Faktor, Aufladetempo samt Host-Deckel), Alarm in Spinne, Lauscher, Brecher (Sicht und Gehör), `worn` synchronisieren. Tests: `tools/test_talismans.tscn` (Zahlen jeder Wirkung, der Heiltrick, Aufladung auf dem Host, Alarm gegen die drei Gegner, Speichern/Laden, Mehrspieler zu zweit).
4. **Anzeige:** Icons endgültig, Tooltip mit Vergleich, Runen der leeren Plätze, Entwicklerknöpfe.
5. **Rig-Punkte:** `art_hero3d.py` exportiert Ohren, Choker, Brust und die Sichtbarkeitsbits; die betroffenen Sheets neu rendern (`art_hero_rebuild.py` und die Einzelskripte der Aktionsbögen); `hero_rig.json` wächst.
6. **Ebene und Teile:** `TalismanLayer`, Armband in `_draw_arm`, getragene Kunst und Leuchtbilder aus `art_talismans.py`, die Puppe im Inventar, Vorschau `tools/preview_talismans.tscn -- --capture=/abs.png` (alle Blickrichtungen × Tag/Nacht).
7. **Gefühl:** Klänge, Anlege-Funkeln, Schlucken-Blitz, Summen der Ohrringe.
8. **Beschaffung und Zahlen:** Beute- und Truhentabellen, Händler, Abstimmung gegen echte Treffer (kleine Simulation wie `sim_refine.py` für Schaden und Wuchtschlag).

## 11. Entscheidungen

Für alle gilt der **Standard in Fettdruck**, wenn nichts anderes gesagt wird.

1. **Was heißt "25 % von allem Schaden tanken"?** **Schlicht −25 %** nach der Rüstung. Alternative: **Leerenschuld**, der geschluckte Teil läuft als kleiner Zeitschaden über zehn Sekunden zurück (spannender, aber härter und schwerer lesbar).
2. **Gilt die Alarmreichweite auch für den Köder der Nacht?** **Nein**, nur im Feld (Abschnitt 4c).
3. **Freie Plätze oder feste Plätze** (Hals / Ohr / Hand)? **Frei**, mit der Regel "je Gattung nur eines" (Abschnitt 3a).
4. **Tauschen oder Ablehnen** beim Anlegen eines zweiten Stücks derselben Gattung? **Automatisch tauschen, beim gezielten Klick auf den falschen Platz ablehnen.**
5. **Woher kommen die ersten drei?** Mine-Truhe / Leerenbrecher / Mornath (Abschnitt 8).
6. **Nachteil bei Legendären?** **Keiner** (Idee 3 bleibt offen).
7. **Namen und Texte:** alles Platzhalter, die Dialogtexte schreibt der andere Agent.
