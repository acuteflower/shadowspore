# Farming: Felder (ACKER)

Stand: 2026-11-10. Gebaut: Schritte 1-7 unten. Alle Texte sind Platzhalter.

## Idee

Gustav fertigt die erste **Hacke** oder **Gießkanne** (Werkbank, `recipes.json`, `"unlocks": "farming"`); ab diesem Moment schaltet die Stadt die Kategorie **ACKER** im Baumenü frei (Banner „FELDER FREIGESCHALTET“, gespeichert als `unlocks`). Ein **Feld** ist ein normales Stadtteil (`field`, 3 x 3 Beete à 16 px, Raster 16, frei platzierbar, gespiegelt egal), aber *Boden*: kein Collider, `walk: true`, Oberfläche `field` (Schritte matschig, 0.95 Tempo).

Auf dem Feld:

1. **Hacke** (Hotbar, Schwung) bricht ein Beet auf. Nochmal geharkt hält es länger.
2. **Samen aus der Wildnis** im ausgewählten Hotbar-Slot, E = SÄEN. Wilde Pflanzen geben beim Pflücken manchmal Samen (`wild_seeds` in `data/farming.json`: Erdknolle, Glutkarotte, Nachtrübe, Wundblatt).
3. **Gießkanne** (Schwung) wässert. Nur über Nacht *gewässerte* Beete wachsen (Regentage wässern alles). Nasse Erde ist dunkler und glitzert.
4. **Ernte**: E = ERNTEN, Pflück-Animation, Drops. Wer jede Nacht gegossen hat (`m == 0`) bekommt +1 (`ripe_bonus`). Wundblatt wächst nach (`regrow`), ein Samen kommt manchmal zurück (`seed_back`).
5. Ein leeres Beet, das 3 Tage niemand anfasst (`fallow_days`), wird wieder rauer Boden.

Später: Samen, die **nur** auf Feldern wachsen (`origin: "field"` am Crop, Quellen: Truhen, Händler, Quests). Der Hook ist da, es gibt noch keine.

## Der Boden (`FieldSoil`)

Kein Sprite-Set, sondern pro Pixel gemalt (`FieldSoil.render`) aus der Weltposition und der vorzeichenbehafteten Distanz zur **Vereinigung aller Feld-Rechtecke**:

- Nachbarfelder verschmelzen zu einem großen Beet (der Pixel innerhalb eines *anderen* Feldes bleibt transparent, das andere Feld malt ihn).
- Außenkante: dunkle Tinte, helle Oberlippe oben/links, dunkle Unterlippe, außen bröselt sie in Krümel und Grasbüschel aus (Rauschen aus ganzzahligen Hashes, auf allen Peers identisch).
- Beetzustand: roh (festgetretene Erde, Kiesel, Gras), gehackt (Furchen alle 4 px), nass (dunkler, Glanzpunkte).
- Das Bild ist eine dynamische `ImageTexture` (`TownStructure._load_picture`), neu gemalt wenn sich Beete oder Nachbarfelder ändern.

## Dateien

| Was | Wo |
|---|---|
| Regeln (rein) | `src/town/farm_rules.gd` |
| Host-Zustand, RPCs, Save | `src/town/farm_manager.gd` (Kind `Farm` von `TownManager`, `town.farm`) |
| Bild des Feldes | `src/town/farm_field.gd`, `src/town/field_soil.gd` |
| Ein Beet (Pflanze, Treffer, E) | `src/town/field_cell.gd` |
| Daten | `data/farming.json`, `data/town.json` (`field`, Kategorie `farm`), `data/items.json`, `data/recipes.json`, `data/weapon_classes.json` (`hoe_1h`, `can_1h`), `data/terrain.json` (`field`) |
| Kunst | `py -3 tools/art_crops.py [preview.png]` (Pflanzen, Samentüten), `py -3 tools/art_weapons.py only hoe_basic watering_can` |
| Klänge | `py -3 tools/audio_farming.py` -> `assets/audio/farming/` |

Beet-Zustand (Dictionary je Zelle): `t` gehackt, `w` gewässert (Tag+1), `c` Pflanze, `a` Stufe, `p` bewässerte Nächte in der Stufe, `m` verpasste Nächte, `u` letzter Arbeitstag.

## Host, Netzwerk, Speichern

- Der Host entscheidet (`host_hit`, `_host_plant`, `_host_harvest`, `_on_day_started`), `_rpc_cell` / `_rpc_day` (authority, call_local, reliable) verteilen. Die Ansicht (`FarmField`/`FieldCell`) lädt nur nahe am Spieler, sie ist reine Darstellung.
- Werkzeug-Schlag: `HarvestHurtbox` (Ebene 5) je Beet, 24 px angehoben wie alle Bodenziele; `GameCursor` zeigt die Erntehand, wenn `spec().tool` zum Werkzeug passt.
- Saat kommt aus dem **ausgewählten Hotbar-Slot** (`inventory.slots[selected]`), nicht aus `active_stack()` (das kennt nur Werkzeuge/Waffe).
- Save: `town.export_state()` hat `farm` und `unlocks`; Beitretende bekommen beides im Stadt-Snapshot. Ein abgerissenes Feld nimmt seine Beete mit (`field_removed`).
- Entwicklerstand: `debug_build_all` (FERTIGE STADT) schaltet `farming` frei und baut ein Feld.

## Prüfen

- `Godot --headless --path . --fixed-fps 60 tools/test_farming.tscn` -> `FARMING OK` (Regeln, Daten, Bodenmalerei inkl. Nachbarn, Welt: Freischaltung, Platzieren, Hacken, Gießen, Säen, Wachsen, Ernten, Speichern, Abreißen).
- Optik: `Godot --rendering-driver opengl3 --path . tools/preview_farm.tscn -- --capture=/abs.png [--night] [--zoom=3]`.

## Nicht gebaut / Ideen

- **Wasservorrat der Kanne** (nachfüllen am Fluss/Fass) — jetzt unendlich.
- Feld-exklusive Samen, Düngen, Vogelscheuche (hält Krähen fern, passt zum Krähen-System), Bewässerungsrinne aus dem Fluss, Zaunbonus.
- Nachtfrüchte: Glutkarotte und Nachtrübe leuchten im reifen Zustand (Glow-Sheet), im Feld zieht das Licht Glühwürmchen an (noch nicht angebunden).
- Gustav-Dialogzeile zur Hacke, Quest/Hinweiskarte (`HintCard`) für den ersten Acker.
- Kochen: Ernte-Items sind die vorhandenen Wildpflanzen-Items.
- Kunst entstand per Python-Generator (`art_crops.py`), nicht über den Terra-Subagenten (nicht verfügbar).
