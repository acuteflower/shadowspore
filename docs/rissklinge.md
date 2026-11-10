# Himmelsriss (`sword_rift`), das erste legendäre Schwert

Stand 2026-11-10. Ein Schwert, das nur aus einer **Rissfeder** entsteht (Mornaths Beute, `docs/rissfeder.md`) und in Torbens Esse zur Klinge geschlagen wird. Es hat eine eigene Waffenklasse, einen eigenen Rechtsklick aus zwei diagonalen Hieben und ein Zusammenspiel mit der Rissfeder um den Hals.

## Idee
Mornath ist ein Rabe, der den Himmel aufreißt. Das Schwert ist eine einzelne schwarze Schwungfeder, die man zur Klinge gehärtet hat: Federform statt Kreuzform, ein violetter Riss als Grat, Flügelfedern als Parierstange. Seine Besonderheit ist der Riss: Es lässt Licht dort aufspringen, wo es hinzielt.

## Werte (`data/items.json` `sword_rift`)
Legendär, `main_hand`, Klasse `sword_rift` ("Himmelsklinge"), Schaden 40 (Leerenklinge 30), Tempo 1.15, Reichweite 36, Rückstoß 60, 3 Verzauberungsplätze, veredelbar (bis +15). Karte: vier `specials` (Name + Text, `ItemTooltip` zeigt sie als "perk"-Zeile mit Beschreibung).

## Klasse (`data/weapon_classes.json` `sword_rift`)
Kombination wie `sword_1h` (gleiche Upgrade-Schläge). Der **dritte Schlag (Stoß)** trägt `"rift": "line"`: **SPITZENRISS**, eine kurze Rissbahn (72 px, 45 % des Waffenschadens), unabhängig vom Multiplikator des Stoßes.

### Rechtsklick (`secondary`, Art `rift_slash`)
Kein Aufladen, kein Wuchtschlag: Der Rechtsklick ist eine **Kette aus zwei diagonalen Hieben**, jeder schießt aus der Klingenspitze einen Fächer aus Federn. Sie laufen über die normale Schwing-Pipeline (`AttackComponent._alt_start` -> `_alt_swing` RPC -> `_server_alt`; Körper = Vorhand-/Rückhandblock des Angriffsblatts, die Klinge folgt ihrer eigenen Diagonale in `_update_pose`, `_chop_blade`), Werte in `weapon_classes.json` `sword_rift.secondary` (`steps`, `window`). Gehen und Lunge wie bei jedem Hieb, Lärm x1.3.
1. **RISSSCHNITT** (erster Rechtsklick, 20 Ausdauer): von rechts oben nach links unten. Klingenhieb 150 % Waffenschaden, dazu **5 Rissfedern** im 40-Grad-Fächer, 90 px weit, je 40 % Schaden; ein Gegner nimmt höchstens 3 Federn (kurz hinter der Klinge ist der Fächer noch eng, wie eine Schrotladung).
2. **HIMMELSKREUZ** (zweiter Rechtsklick innerhalb von 0,6 s nach dem Ende des ersten, 15 Ausdauer): der Gegenhieb von links oben nach rechts unten, zusammen mit dem ersten ein X. 200 % Schaden, **7 Federn** im 70-Grad-Fächer, 110 px weit, je 45 %, höchstens 3 pro Gegner. Danach beginnt die Kette wieder mit dem ersten Hieb; verstreicht das Fenster, auch.
- Ein Rechtsklick **während** des ersten Hiebs wird vorgemerkt (350 ms) und startet den zweiten, sobald der erste endet.
- Die Federn beginnen an der Klingenspitze (Reichweite x 0,8): nahe Ziele trifft nur die Klinge, weiter draußen ganze Federn. Der Host schickt jede Feder mit ihrer Stoppdistanz an die FX (`_volley_fx`), sie bleibt im Ziel stecken und verglüht (`FeatherVolley`).
- Regeln rein in `HeavyRules` (`rift_step`, `rift_cost`, `rift_window`, `is_rift_slash`); die normale Schwertklasse behält ihren Wuchtschlag.

## Federbund (Zusammenspiel mit der Rissfeder)
Trägt sie die Rissfeder (`perks` enthält `ward`) und der Letzte Flügelschlag ist noch in der Pause, verkürzt **jeder vom Himmelskreuz getroffene Gegner** die Pause um 8 s, höchstens 32 s je Hieb (`TalismanComponent.shorten_ward`, Werte `ward_refund` / `ward_cap` im Fächer des zweiten Hiebs). Der erste Hieb verkürzt nichts. Ist der Flügelschlag bereit oder die Feder nicht angelegt, passiert nichts. Hinweis: Zum Anlegen muss ein Talismanplatz offen sein (Stufe 5).

## Rezept (Torben, 5. Reiter BESTELLEN, `data/recipes.json` `sword_rift`)
`by: "npc"`, `npc: torben`, Vertrauen 40, Arbeit 300 s. Material: 1 `sword_iron`, **1 `rissfeder`** (muss im Beutel liegen, nicht angelegt sein), 4 `iron_plate`, 2 `void_slag`, 2 `shadow_core`. Die Rissfeder ist die Sperre: ohne sie meldet `order_block` den fehlenden Stoff.

## Aussehen und Effekte
- Kunst `py -3 tools/art_weapons.py` (`rift_sword`: Federklinge mit Widerhaken, Grat-Material `ridge`, Rabenvioletts `raven`/`crack`, Flügelfedern als Parierstange, Federspitze als Knauf, Edelstein `c07bff`). Icon, `_held.png`, `_held_rot.png` werden wie bei den anderen Waffen erzeugt. Kontrollbild: `tools/preview_weapons.tscn`.
- Der `fx`-Block des Items (`motes`, `trail_edge`, `trail_core`, `sounds`) färbt Schwingpartikel und Schweif und wählt den Klangordner; ohne ihn bleiben alle anderen Schwerter unverändert (`AttackComponent._load_fx`).
- `RiftFx` (src/fx): `lane` (die Bahn des Spitzenrisses schießt aus der Klinge, schließt sich vom Heft her, gibt Federn ab). `FeatherVolley` (src/fx): der Fächer der Hiebe, Federn mit schmaler violetter Spur, leichtem Schwanken, bleiben im Ziel stecken und verglühen in Funken. Pixel, ungelit, Echtzeit. Gemeinsame Feder: `FeatherBurst.draw_feather`.
- Klänge `py -3 tools/audio_rift.py` -> `assets/audio/rift/{swing,line,volley}.wav` (synthetisierte Platzhalter).

## Technik
- `HeavyRules`: `rift_step(cfg, item, stage)` (Hiebdaten inkl. `diag`-Winkel und `volley`), `rift_cost`, `rift_window`, `rift_steps`, `is_rift_slash`, `rift_data(cfg, "passive")` für den Spitzenriss.
- `HitScan.lane(from, origin, dir, length, half_width, mask)`: Rechteck-Abfrage entlang einer Bahn; `HitScan.fan` für Klinge und Federfächer.
- `AttackComponent` (Host): `_server_alt` -> `_hit_scan` (Klinge) -> `_volley` (Federn, pro Ziel gedeckelt, Federbund); `_rift` für die Bahn des Stoßes; `_rift_fx` / `_volley_fx` RPCs spielen die Effekte auf jedem Peer. Eingabe: `Player._update_alt` (Rechtsklick -> `alt_press`).
- Dev: Pause -> ENTWICKLER -> HIMMELSRISS BEKOMMEN (Host; Schwert in die Hand), dazu RISSFEDER BEKOMMEN.

## Tests
`Godot --headless --path . --fixed-fps 60 tools/test_rissklinge.tscn` (Daten, Regeln, Klingen- und Federschaden gegen echte Hurtboxen, Kette und Vormerkung, Spitzenriss, Federbund, Effekte, Karte) und `tools/test_smithy_shop.tscn` (Bestellung beim Torben).

## Grenzen
Kunst und Klänge sind Platzhalter von mir, nicht vom Art-Agenten. Der Schwingschweif ist ungeprüft im laufenden Spiel; die Optik von Hieben und Federfächer ist nur durch den Headless-Test (Lebenszyklus) abgesichert, nicht visuell. Die Körperanimation nutzt die Vorhand-/Rückhandblöcke des normalen Angriffsblatts, kein eigener Eintrag für die Diagonalen. Zwei-Prozess-Netzwerktest fehlt.
