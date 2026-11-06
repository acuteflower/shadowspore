# Ellie am Lagerfeuer

Nach dem abgeschlossenen Lagerfeuergespräch (`fire_seated`) bleiben beide Sitzplätze bei Valdrics Hütte nutzbar: der Stumpf östlich und der Baumstamm südlich des Feuers. E setzt Ellie auf einen freien Platz. Sie sitzt entspannt, atmet ruhig und wählt zwischendurch zufällig Händewärmen, Strecken, Haarrichten, Umschauen oder eine kleine Haltungsänderung. E oder eine Bewegungsrichtung spielt das Aufstehen; danach kann sie wieder normal laufen. Ein von Valdric oder einem anderen Spieler belegter Platz bietet keine Interaktion an. Vor dem Gespräch startet derselbe Sitzplatz weiterhin die vorhandene Storyszene, in deren ruhigen Sitzphasen dieselben Gesten vorkommen.

`CampfireSeat` erweitert die bestehenden `StorySpot`s. `RestComponent` prüft Anfragen auf dem Host (Eigentümer, Entfernung, Belegung, Gesundheit und laufende Aktionen), spielt Annäherung, Hinsetzen und Aufstehen auf allen Peers und liefert beitretenden Peers den aktuellen Sitzstand. Der Quest-Fortschritt liegt wie bisher beim jeweiligen Spieler; dort wird die Freischaltung geprüft. Schaden beendet das Sitzen sofort. Teleports und entfernte Sitzplätze lösen die Sitzsteuerung. Inventar, Quests, Gesundheit und Uhrzeit werden vom freien Sitzen nicht verändert.

Die Richtungen und Gesten kommen aus `tools/art_hero_sit.py` und `tools/art_hero_rest.py`, mit Ellies bestehendem Pixelrenderer. Beide Atlanten enthalten acht echte Richtungen und eigene Verletzungsmasken. Der Stumpf blickt standardmäßig nach Westen zum Feuer, der Baumstamm nach Nordwesten; neue Plätze können ihren Sektor über `facing_sector` wählen. Timing und Clips stehen unter `sit` und `rest` in `data/hero_rig.json`. Gesten starten zufällig nach 5–10 Sekunden und wiederholen sich nicht direkt. Der Host synchronisiert die Auswahl und übermittelt bei späterem Beitritt den aktuellen Zustand. Die bestehenden Lagerfeuer-Dialoganimationen haben Vorrang.

Prüfungen:

- `Godot --path . tools/test_rest.tscn -- --capture`: beide Plätze, Gesten, E/Bewegung zum Aufstehen, Belegung, Schaden, Teleport, unverändertes Inventar und Queststand. Spielansichten unter `/tmp/ellie-rest-{east,south,warm,stretch}.png`.
- `Godot --headless --path . tools/test_rest_network.tscn -- --server` und ein zweiter Prozess ohne `--server`: Host-/Client-Sitzen, Wiederherstellung des Sitzstands und Aufstehen, Port 17919.
- `Godot --headless --path . tools/test_debug_wake.tscn`: der Entwickler-Sprung schaltet die freien Plätze ebenfalls über den korrekten Storyzustand frei.
- `Godot --headless --path . tools/test_ellie_sitting.tscn`: acht Richtungen, Masken, Gestenauswahl und Priorität der Storyaktion.
