# Der Brunnenplatz – das Herz der Stadt

Status: **Stufe 1 gebaut (2026-11-13).** Spätere Ausbaustufen (größerer Brunnen, Markttage mit fahrendem Händler, Abendfeste, Handel mit anderen Städten) sind gewollt, aber noch nicht entworfen.

## Idee
Nach dem Erneuern der Hütte ist das Land um sie herum zwar beansprucht (Licht, Baumodus), aber noch keine Stadt. **Erst der Brunnenplatz gründet sie.** Er ist das erste und einzige, was man dann bauen kann; alle anderen Teile brauchen ihn (`needs: "plaza"`). Er wird das Zentrum: Von ihm gehen die Wege aus, die Karte setzt die Stadtflagge auf ihn, die Stufen-Zeremonie läuft von ihm aus.

## Aussehen (erste, bescheidene Stufe)
`python3 tools/art_plaza.py [kontakt.png]` schreibt nach `assets/town/`:
- `plaza.png` (208×136): runder Platz aus Kopfsteinen, in Ringen um den Brunnen gelegt (Voronoi-Steine auf Ringpunkten, für die 3/4-Sicht abgeflacht), Licht von oben links, gewölbte Steine, dunkle Fugen, Moos in den äußeren Fugen, am Rand fehlende Steine und ein ausfransender Saum, durch den die Wiese bricht, sechs kleine Blumentuffs. Farben = Stadtstein (`art_town` STONE_L).
- `plaza_fountain.png` (4 Frames à 56×48, Fuß (28, 41)): niedriges rundes Becken aus hellerem behauenen Stein, Wasser mit Ringwellen, kleine Säule mit Schale, aus der Wasser rinnt. `_glow`: nur das Licht des Wassers (nachts sanft teal).
- `plaza_preview.png`: beides zusammen für das Baumenü.

## Technik
- Teil `plaza` in `data/town.json`, Kategorie `heart` („PLATZ“, die erste), `limit` 1 (`check_place`: „STEHT SCHON“), Kosten 12 Stein + 4 Holz, 14 s, `reach` 112, `wave` 24, `worth` 10, `aura` teal, `paths` true, Oberfläche `stone`.
- **Boden + stehender Brunnen:** `walk` true (Bodenbild auf z −9, keine Fußkollision), neuer Schlüssel `stand` {texture, frame, feet, frames, fps, glow, solid, window}: `TownStructure._make_stand` setzt den Brunnen als eigenes Sprite an die Füße des Teils (wird mit den Leuten sortiert), mit eigener Kollision und eigenem Aufbau-Fenster. Die Füße des Teils sind deshalb die Brunnenunterkante; `foot_drop` (44) lässt die Fußfläche unter die Fußlinie reichen (`TownRules.foot_rect`, `snapped_position`; Seilrahmen, Splitter, Aura folgen `_foot_local()`).
- Beim Setzen blockiert auf einem begehbaren Teil nur der Brunnen selbst („JEMAND STEHT DARIN“), nicht die ganze Fläche.
- **Gründung:** `TownManager.founded` bleibt das Beanspruchen bei `rebuild_done` (technisch nötig für Licht und Baumodus), aber kein Banner mehr. Ist der Platz fertig (`built` → `_found_heart`, 2,6 s nach der Weihe): großes Banner „STADT GEGRÜNDET · <Name> · DER BRUNNEN IST IHR HERZ“ mit Glocken. `has_heart()`, `heart()` (Platzmitte, sonst die Hütte). Das Banner beim Betreten kommt erst mit Platz; der STADT-Tab sagt „NOCH NICHT GEGRÜNDET · BAUE DEN BRUNNENPLATZ“.
- **Wege:** `_host_make_way`: steht (oder entsteht) ein Platz, führen alle neuen Trampelwege zu seinem Rand (`_square_rim`, 12 Punkte um die Ellipse); der Platz selbst bekommt einen Weg von seinem Rand zur Hüttentür.
- **Quest:** `town_start` hat den Schritt `build_plaza` („BAUE DEN BRUNNENPLATZ“, Flag `built_plaza`, Hinweis `build`) vor dem Lichtpfosten. `QuestComponent._migrate_plaza`: alte Spielstände, die schon weiter waren, gehen auf diesen Schritt zurück, solange kein Platz steht. Alte Städte ohne Platz können erst wieder bauen, wenn sie einen gesetzt haben.
- FERTIGE STADT (`debug_build_all`) setzt den Platz als erstes Teil.

Blick: `Godot --rendering-driver opengl3 --path . tools/preview_town_build.tscn -- --dir=/abs --piece=plaza [--night]`.
