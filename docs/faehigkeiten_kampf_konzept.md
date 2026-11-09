# Fähigkeiten, Teil 1: Kampf, Schleichen, echte Icons

Konzept und Umsetzung (Stand 2026-11-09). Baut auf dem Schleiergeflecht (`docs/skill_tree.md`) auf. Der Graph
bleibt unter **F**; dieses Dokument macht aus dem rein kosmetischen Gerüst zum ersten Mal einen Baum mit echten
Upgrades – zuerst auf der Kampfseite.

## 1. Was der Spieler sehen und tun soll

| Ast | Fähigkeit | Von Anfang an | Upgrades |
|---|---|---|---|
| KAMPF | **DREIKLANG** – Schwertkombo mit Linksklick: Vorhand, Rückhand, Stoß | ja | **AUFWÄRTSHIEB** (4. Schlag) ab **Stufe 5** für **1 Punkt**, danach **WIRBELKLINGE** (5. Schlag) ab **Stufe 15** für **2 Punkte** |
| BEWEGUNG | **ANTRITT** – Sprinten mit Dash | ja | keine |
| BEWEGUNG | **SCHLEICHEN** – zweite Fähigkeit des Astes | ja | keine |
| SCHATTEN | **SCHATTENBLINK** | ja | noch keine (später) |

Alle übrigen Knoten bleiben kostenlose **Platzhalter** (erkunden, keine Wirkung).

### Fähigkeitspunkte
* Es gibt **einen** Topf: `Stufe - 1` Punkte (so stand es schon in der Ansicht, jetzt wird er echt ausgegeben).
* Frei = `Stufe - 1 - ausgegeben`. Beispiel: Stufe 5 → 4 Punkte, Aufwärtshieb (1) → 3 frei; Stufe 15 → 14 Punkte,
  Wirbelklinge (2) → noch 11 frei. Für die Kampfseite werden nur 3 Punkte gebraucht; der Rest wartet auf die
  anderen Äste.
* Es gilt die **erreichte** Stufe (`ProgressComponent.level`), nicht die im Fortschritts-Fenster eingesammelte –
  Fähigkeitspunkte sind kein Eintrag der Stufenbelohnungen.
* Lernen ist endgültig (kein Zurücksetzen in diesem Schritt; Rückgabe/Umskillen bleibt eine offene Frage).

### Upgrades lernen
* Upgrades sind **keine eigenen Orbs**. Sie wachsen an der **Blume ihrer Fähigkeit** (DREIKLANG) selbst: Der
  4. und 5. Schlag sind Upgrade 1 und 2 *dieser* Blume. In `data/skills.json` sind es Knoten mit `upgrade: true`
  und `parent` (Kette: `combo_four` → `combo_five`), ohne `pos`; der Graph zeichnet sie nicht als Knoten.
  Zustände je Upgrade (`SkillTreeComponent.upgrade_state`):
  * **locked** – Stufe fehlt („AB STUFE 5“).
  * **blocked** – für Upgrade 2, solange Upgrade 1 nicht gelernt ist.
  * **short** – Stufe passt, Punkte reichen nicht.
  * **ready** – lernbar: goldene Knospe auf der Blume, „UPGRADE BEREIT“, „HALTEN ZUM LERNEN“.
  * **learned** – Knospe gefüllt, die Blüte hat mehr Blütenblätter.
* Lernen = **Halten auf der Blume** (LMB auf die Blume oder die Knospe unten rechts, Enter/Controller A), 0,95 s;
  gelernt wird das **nächste bereite Upgrade** der Fähigkeit. Loslassen bricht ab. Der Host prüft und bestätigt,
  dann kommen Lichtwelle, Funken und ein neuer Ton (`learn.wav`); Spielwerte ändern sich erst danach.

### Die Blume zeigt die Upgrades
Die Wurzelblume wird sichtbar „mehr“, wenn sie Upgrades hat:
1. **Upgrade-Knospen auf dem Rand.** Für jedes Upgrade sitzt eine kleine Knospe oberhalb der Blume: dunkel und
   hohl = noch nicht da, goldener Puls = bereit, gefüllt = gelernt. Man sieht aus der Ferne, wie viele Upgrades
   es gibt und wie viele gewachsen sind.
2. **Die Blume wächst.** Jedes gelernte Upgrade gibt der Blüte 2 Blütenblätter mehr (10, 12, 14; ab 10 mit
   Kronenring).
3. **Hinweis unter dem Namen.** „UPGRADE BEREIT“ (golden, pulsierend) oder „UPGRADE AB STUFE 5“; die Blume
   bekommt einen goldenen Hof, solange etwas lernbar ist. Fähigkeiten ohne Upgrades (Antritt, Schleichen,
   Schattenblink) zeigen nichts davon, im Detailblock „KEINE UPGRADES“.

### Detailblock (unten links)
* Wurzel: Ast/„ERLERNT“, Name, Beschreibung, Detailzeile, darunter die Upgrades als Liste („1 AUFWÄRTSHIEB  ▸ ab
  Stufe 5, 1 Pkt“ mit Zustand) bzw. „KEINE UPGRADES“.
* Die Punkteanzeige oben rechts zeigt jetzt **freie Punkte**: „3 PUNKTE FREI“.
* Aktionsast unten rechts (für die gewählte Blume): „HALTEN ZUM LERNEN“ + Name/Kosten des nächsten Upgrades, „UPGRADE NOCH GESPERRT“ + Anforderung, „ALLE UPGRADES ERLERNT“.

## 2. Gameplay-Umsetzung

### 4. und 5. Kombo-Schlag
* `data/weapon_classes.json` `sword_1h.combo` bekommt zwei Schritte mit `requires` (Skill-ID) und `block`
  (Körperanimation):
  * Schritt 4 **Aufwärtshieb**: schneller, weiter Rückschnitt von unten nach oben, `sweep +1`, Bogen 150°,
    Windup 0,06 / Aktiv 0,08 / Erholung 0,17, Schaden ×1,25, Reichweite ×1,1, Rückstoß ×1,3.
  * Schritt 5 **Wirbelklinge**: voller Kreis um die Heldin, `sweep -1`, Bogen 330° (Host nutzt zwei Fächer),
    Windup 0,13 (sie holt Schwung) / Aktiv 0,17 / Erholung 0,4, Schaden ×1,8, Reichweite ×1,15,
    Rückstoß ×2,2, mehr Kamerawackeln.
* `AttackComponent` zählt nur Schritte, deren `requires` erfüllt ist (`_combo_size`/`_unlocked_steps`), der Host
  lehnt gesperrte Schritte ab (`_server_swing`). Ohne Upgrades bleibt alles beim Alten (3 Schläge). Andere
  Waffenklassen haben keine `requires`-Schritte und ändern sich nicht. Nach dem letzten freigeschalteten Schlag
  beginnt die Kombo wieder bei 1.
* `AttackComponent.animation_state()` liefert für Schritte mit `block` ≥ 3 den Block der neuen Animationsdatei.

### Animationen (Heldin)
* Neues Blatt `assets/characters/player_combo.png` (+ `_blood`) aus `py -3 tools/art_hero_combo.py`, gleicher
  Ellipsoid-Renderer wie alle Heldinnenblätter, **bestehende Blätter bleiben pixelgleich**: 2 Angriffe × 7
  Beinvarianten (0 stehend, 1–6 Laufzyklus) × 6 Schlüsselbilder, 8 Richtungen. Rig-Einträge `combo_shoulder` /
  `combo_hand` in `data/hero_rig.json`. `Player._animate` wählt Blatt 12 für `animation_state().x >= 3`.
* Aufwärtshieb: tiefer Ausfall links, Hand startet knapp über dem Boden (hinten rechts), schneidet in einem
  Bogen steil nach oben/links, Oberkörper kippt zurück, Haar und Mantelschöße ziehen nach.
* Wirbelklinge: Windup mit eingedrehtem Oberkörper, dann dreht der Oberkörper ca. 330° (`twist`), die Hände folgen
  einem Kreis um den Körper, Standbein bleibt, Spielbein schwingt mit; ausgefedert zurück in die Ruhe.

### Schleichen
* Wird zur zweiten Fähigkeit des Bewegungs-Astes (`sneak`, `root`, Elternlinie zu ANTRITT). Wirkung bleibt wie
  heute: Taste halten, gebückte Haltung, Gegner sehen nur halb so weit (`StealthComponent.sneak_detection_multiplier`
  wird live im Detailblock angezeigt), Waffe wird weggesteckt. **Keine Upgrades**, wie beim Sprinten.

### Zustand, Netzwerk, Speichern
* `SkillTreeComponent` hält zusätzlich `_learned` (Host-Wahrheit pro Spieler). `request_learn(id)` → Host prüft:
  Besitzer, Upgrade-ID, Elternknoten gelernt/erwacht, Stufe, freie Punkte. Nur der Besitzer bekommt seinen Zustand
  (`_state(discovered, learned, new_id)`); andere Spieler sehen nur die Schläge selbst (die RPCs tragen den
  Schritt-Index, jede Maschine spielt ihn ab).
* Speichern: `player.skill_tree.learned`. Beim Laden werden unbekannte IDs, Duplikate, fehlende Vorgänger und
  Einträge ohne Stufe/Punktedeckung verworfen (Reihenfolge beliebig). Alte Spielstände starten ohne Upgrades.
* Der Host liest für Wirksamkeit (Kombolänge) seine eigene Kopie des Spielers, der Besitzer die gespiegelte.

## 3. Icons

Alle alten Linienglyphen (`sword`, `stride`, `rift`) fliegen raus. Neue Pixel-Icons, 13×13, in der Spielpalette,
eine Form pro Fähigkeit, ein Farbverlauf aus dem Ast-Ton (Schatten/Basis/Licht/Glanz) plus warmer Funke:

| ID | Fähigkeit | Bild |
|---|---|---|
| `combo3` | DREIKLANG | Schwert nach rechts oben, drei Schnittbögen dahinter |
| `combo4` | AUFWÄRTSHIEB | steil aufsteigender Halbmond-Schnitt mit Klingenspitze |
| `combo5` | WIRBELKLINGE | Schwert in einem geschlossenen Wirbelring |
| `sprint` | ANTRITT | geflügelter Stiefel mit Tempostrichen |
| `sneak` | SCHLEICHEN | leiser Fußabdruck auf Zehenspitzen mit verblassender Spur |
| `blink` | SCHATTENBLINK | Riss im Dunkel mit zwei Funken und gepunkteter Bahn |

* Quelle: `py -3 tools/art_skill_icons.py` (ASCII-Karten, deterministisch). Es schreibt die generierten Karten in
  `src/ui/skill_icon_art.gd` (zwischen Markern, wie `art_cursor.py`) und eine Kontaktsheet-Vorschau in
  `docs/img/skill_icons.png` (alle Icons ×6, Tag-/Nachtton).
* `SkillIcons` (src/ui/skill_icons.gd) backt pro Icon und Ton eine gecachte Textur; die Blumen zeichnen 1× in der Mitte.

## 4. Nicht Teil dieses Schritts
Upgrades für Bewegung/Schatten, Zurücksetzen/Umskillen, HUD-Hinweis „Fähigkeitspunkt frei“, neue Töne außer dem
Lerngeräusch (`learn.wav` aus `tools/audio_skills.py`), Balancing der 4./5.-Schlag-Werte gegen Nachtkreaturen.

## 5. Prüfen
`tools/test_skill_tree.tscn` (erweitert: Zustände, Stufe/Punkte, Lernen, Speichern, Kombolänge, abgelehnte
Schritte, Icons), `tools/test_skill_tree_network.tscn` (Besitzerisolation und abgelehnte Lernanfragen),
`tools/test_heavy.tscn` und `tools/test_item_throw.tscn` als Regression. Vorschau der neuen Animationen:
`py -3 tools/art_hero_combo.py contact out.png <sektor> <block>`.
