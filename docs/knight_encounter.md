# Ritterfund und Angriffseinführung

Der Abschnitt ist eingebaut. Nach den Wächtern führt „Hilfe finden“ zum tatsächlichen Pfad bei Tile **(489,685)**. Wenige Schritte rechts daneben sitzt der von der Leere angegriffene Ritter bei **(493,685)**, an einem umgestürzten Stamm. Die Position wurde gegenüber dem ungefähren Screenshot-Anker an den vorhandenen gebackenen Pfad angepasst und auf ebenen Boden geprüft. Bewuchs um den Fund wird freigehalten.

Mit der gebundenen Interaktionstaste (E) wird der Ritter untersucht. Ein einfaches Schwert (`sword_basic`) fällt mit kurzem Metallgeräusch heraus. Ellie hält mit einer ruhigeren, nachdenklichen verletzten Mimik inne: „Was sind das nur für Spinnendinger …?“, „Du hast es also auch nicht geschafft.“, „Das Schwert wird mir bestimmt noch nützlich sein.“ Die Dialogvariation verwendet die vorhandene Pixel-Art mit gesenktem/geschlossenem Blick; sie ist kein neues Porträt-Asset.

Das Schwert wird über die vorhandene automatische Beuteaufnahme aufgenommen, wenn im Rucksack Platz ist. Es bleibt andernfalls liegen und verfällt nicht. Danach führt eine Karte zum Inventar und Rechtsklick-Ausrüsten in der Haupthand. Die nächste Karte führt in **Hieb → Gegenhieb → Stich** ein, zeigt die gebundene Angriffstaste und drei Fortschrittsmarken. Es sind keine Treffer nötig. Nach drei echten, vom Host bestätigten Kombostufen zieht sich die Karte mit dem vorhandenen Blüteneffekt zurück. Nach einer Pause beginnt die Demonstration wieder von vorn. Dann führt die Quest weiter zu Abzweigung und Wegweiser.

Die Figur bleibt verletzt; der Fund heilt nicht und schaltet das übrige HUD nicht frei. Neue Story-Spiele starten ohne die bisherige Testausrüstung, damit das erste Schwert tatsächlich gefunden wird. Die Arena behält ihre Testausrüstung. Bestehende Spielstände behalten ihre vorhandenen Gegenstände.

## Daten und Persistenz

- Platzierung und lokale Freihaltezone: `data/ground.json`, `fallen_knight`.
- Questschritte: `find_knight`, `inspect_knight`, `take_sword`, `equip_sword`, `sword_combo` vor `crossroad` und `sign`.
- `FallenKnight` hält Inspektion und Beuteanspruch einmal pro Spieler, prüft serverseitig Leben und Entfernung, verteilt den Zustand und erstellt Drops über den vorhandenen MultiplayerSpawner. Story-Drops sind dem jeweiligen Spieler zugeordnet.
- `SaveGame` speichert den Story-Beutestatus mit Inventar und Quests. Ein noch nicht aufgenommenes Schwert wird nach dem Laden genau einmal wiederhergestellt; ein bereits aufgenommenes erscheint nicht erneut. Normale Weltdrops behalten ihre bisherige Lebensdauer.
- Quest-Saves speichern jetzt zusätzlich Schritt-IDs. Dadurch bleiben neue Saves auch bei eingeschobenen Schritten stabil. Alte aktive Abzweigungs-/Schild-Saves ohne Schritt-IDs werden zum neuen Fundabschnitt geführt; bereits abgeschlossene Quests werden nicht neu gestartet.
- `OpeningGuide` koordiniert den einmaligen Dialog, das Ausrüsten und die Einführung. Unterbrochene Dialoge können nach Laden erneut vollständig gezeigt werden; abgeschlossene werden nicht wiederholt. Die Kombofreigabe wird als Questflag gespeichert, unvollständige Kombos werden nicht gespeichert.
- `AttackComponent` meldet nur serverseitig validierte, gestartete aktive Schwertstufen. Übersprungene/zu späte Stufen zählen nicht. Das bestehende Kampfverhalten und die Werte der Waffe bleiben erhalten.

Die Grafik `assets/props/fallen_knight.png` (plus `fallen_knight_glow.png`) wird mit `python3 tools/art_fallen_knight.py` aus dem bestehenden 3D-Pixelrenderer erzeugt: ein gefällter Stamm unserer Bäume (violett geäderte Rinde, türkise Schichtpilze, Moos, Wurzelballen, Schnittfläche mit Jahresringen) und ein sitzender toter Ritter mit Ellies Körperproportionen in abgenutzter Plattenrüstung, Tappert, Schwertscheide und angelehntem Schild. Die Leere frisst ihn: schwarzes Fleisch am Bein und an der Schulter, magentafarbene Adern, ein Schattenfleck mit Ranken und kleinen Blüten am Boden. Die Glühpixel liegen ungelit in einer zweiten Textur und pulsieren, nachts heller.

## Prüfung

`Godot --path . tools/test_knight.tscn -- --capture=/tmp/knight.png`

Prüft unbewaffneten Start, begehbaren Standort, Entfernungskontrolle, einmalige Inspektion, volle Tasche, Save/Load vor und nach Aufnahme, Ablauf des Dialogs, Ausrüsten, Bestätigung jeder Kombostufe und Questfortsetzung. Der Test verwendet eine separate Datei `user://knight_test_only.json` und entfernt sie wieder.

Netzwerk: `tools/test_knight_network.tscn` in zwei Prozessen starten, zuerst mit `-- --server`, danach ohne Argumente (isolierter Loopback-Port 17903). Der Client untersucht zweimal und prüft, dass genau ein Schwert ankommt.
