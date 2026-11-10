# Rechtsklick-Angriff der Primärwaffe: der Wuchtschlag

Rechtsklick ist der **Sekundärangriff der Waffe in der Hand**. Jede Waffenklasse kann in `data/weapon_classes.json` einen Block `secondary` haben; ohne ihn tut RMB nichts (Axt, Spitzhacke, Sichel, Angel). Gebaut ist bisher nur die Art `charge_strike` für `sword_1h` (sword_basic, sword_iron, sword_void). Das "coolere erste Schwert" ist eine eigene spätere Aufgabe.

## Ablauf (Spieler)
1. RMB halten: Ellie zieht die Klinge auf (`draw`, 0.25 s), läuft dabei langsam weiter (Faktor 0.4, kein Sprint/Schleichen, Blick folgt dem Cursor).
2. Ab `charge_min` (0.35 s, nach einem leichten Kombischlag nur `chain_min` 0.2 s) lohnt sich das Loslassen; bei `charge_full` (1.0 s) ist die Ladung voll. Ein kurzer Tipp wird gratis verworfen.
3. Loslassen: Hieb von oben diagonal, Schritt nach vorn (Lunge), viel Schaden, Rückprall, lange Erholung (0.65 s).
4. Wer nach `hold_extra` (1.0 s) auf voller Ladung weiterhält, lässt von selbst los (Ausdauer-Drain `overcharge_drain` 8/s davor).
5. Ein Treffer auf Ellie bricht die Ladung ab (kostet `interrupt_cost` 10 Ausdauer). Ein Menü, das die Maus übernimmt, Blink, Stolpern, Ohnmacht, Story-Sperre oder Tod verwerfen die Ladung kostenlos.
6. Kosten: `stamina_cost` 20 beim Auslösen; ohne die Ausdauer startet keine Ladung.

## Werte (`sword_1h.secondary`)
Schaden x2.2 .. x3.4 (nach Ladung), Rückstoß 2.0 .. 3.0, Lunge 230 .. 300, Kamerawackeln 3 .. 7, Hit-Stop 0.06, Bogen 150 Grad, Reichweite x1.25, Lärm x1.5 (`noise`), `armor_floor` 0.5. Der Floor durchbricht die Frontpanzerung des Leerenbrechers (leichter Schlag wird x0.25, Wuchtschlag mindestens x0.5).

## Code
- `src/systems/heavy_rules.gd` (`HeavyRules`): reine, getestete Regeln (`config`, `has_secondary`, `draw_progress`, `is_ready`, `power`, `overcharge`, `must_release`, `stamina_cost`, `can_start`, `step`, `host_charge`, `charge_key`).
- `AttackComponent`: `begin_charge`, `charge_input(held, ui_took_over, dir, delta)`, `release_charge`, `cancel_charge`, `interrupt_charge`; Abfragen `is_charging`, `charge_amount`, `charge_draw`, `charge_ready`, `is_heavy_swing`, `heavy_key`, `noise_scale`, `charge_move_factor`; Signale `charge_stage`, `heavy_struck`. Der Besitzer sendet Absichten, der Host prüft (`HeavyRules.host_charge` glaubt keine längere Ladung, als er gesehen hat) und führt den Hit-Scan aus (`_server_heavy`); alle Peers spielen Pose, Schweif, Funken und Klänge nach.
- `Player._update_charge()` liest `InputManager.secondary_pressed/held/down` (RMB ist UI-gesperrt, `secondary_down` roh). `Hurtbox.armor_floor` und `CrusherHurtbox` setzen den Floor um.
- Lärm: Listener, Crusher, `NightDirector`, Waldtiere, Krähen und Kaninchen multiplizieren ihre Schwing-Hörweite mit `attack.noise_scale()`.
- Cursor: `GameCursor.Look.CHARGE` (Blüte faltet sich, Ring schließt sich, Gold + vier Funken sobald bereit, Pochen bei voller Ladung).

## Animation
`py -3 tools/art_hero_heavy.py` (Ellipsoid-Renderer von `art_hero3d`) schreibt `assets/characters/player_heavy.png` (Blatt 11: 8 Sektor-Reihen x 70 Spalten = 10 Keys x 7 Beinvarianten, 0 = geplant, 1-6 = Gehphase) und `player_heavy_blood.png`, dazu in `data/hero_rig.json` `heavy_keys`, `heavy_variants`, `heavy_shoulder`, `heavy_hand`. Keys: guard, draw, drawn, strain, apex, chop, impact, rebound, recover, settle (`HEAVY_POSES`). Körperkey aus `attack.heavy_key()`: Laden 0..3, Auslösen läuft auf 4, aktiv 4..6, Erholung 6..9. Kontaktbogen: `py -3 tools/art_hero_heavy.py contact out.png <sektor>`. Danach `Godot --headless --import`. Klinge, Schweif und Hand sind prozedural (`AttackComponent._update_pose`).

Bekannt: Die Klinge steht beim Laden ganz senkrecht, das wirkt etwas steif; ein Kunstdurchgang wäre sinnvoll.

## Klänge
`py -3 tools/audio_heavy.py` -> `assets/audio/heavy/{draw,drop,ready,full,swing,hit,thud}.wav`. Alles synthetisierte Platzhalter.

## Tests und Vorschau
- `Godot --headless --path . --fixed-fps 60 tools/test_heavy.tscn` (59 Prüfungen: Regeln, echte Eingabe, Ausdauer, Abbrüche, Axt ohne Schlag, Crusher-Rüstung).
- Vorschau: `Godot --rendering-driver opengl3 --path . tools/preview_heavy.tscn -- --capture=/abs/ordner --facing=0..7`.
- Offen: Zwei-Prozess-Netzwerktest.

## Eine andere Waffenklasse bekommt RMB
1. In `weapon_classes.json` einen `secondary`-Block mit eigenem `kind` anlegen.
2. `HeavyRules.has_secondary/config` erkennt den Block; für eine neue Art (z. B. Schild-Block, Wurf) eine weitere Regel-Klasse oder ein `kind`-Zweig in `AttackComponent.begin_charge/release_charge`.
3. Neue Körperposen: Blatt wie `art_hero_heavy.py` (eigener Sheet-Index in `Player._use_sheet`, Rig-Einträge, Branch in `Player._animate`).
4. Test nach dem Muster `tools/test_heavy.gd`.

## Rechtsklick des Himmelsriss
Das Himmelsriss nutzt den Wuchtschlag nicht: `sword_rift.secondary` (Art `rift_slash`) ist eine Kette aus zwei diagonalen Hieben ohne Aufladen, die Federn schießen (`HeavyRules.rift_step`, `AttackComponent._alt_start`). Siehe `docs/rissklinge.md`.
