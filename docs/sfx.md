# Sound effects (Higgsfield set, no music)

Stand: 2026-11-10 (Nacht). Alle Clips sind da und verarbeitet (56 Sounds in assets/audio/sfx). Nichts davon wurde angehört; im Spiel nur Parse-/Wildtier-Tests (headless).

## Prinzip
- Jeder Sound entsteht aus **derselben Basis-Beschreibung** (`base` in `tools/sfx_manifest.json`) + einem Satz pro Sound, damit der Satz zusammenpasst. Neue Prompts beginnen mit "The sound starts immediately at 0 seconds with no lead-in silence: ...".
- Rohdateien (wav) -> `py -3 tools/sfx_process.py <raw_dir> [id ...]` -> `assets/audio/sfx/<id>.wav` (mono, Hochpass 70 Hz, Tiefpass 10,5 kHz, Stille vorn weg, auf `max` Sekunden gekürzt, Fade, -3 dBFS + `gain`). Nur numpy.
- Abspielen: `Sfx` (`src/systems/sfx.gd`): `Sfx.at(parent, id, pos, db, pitch_spread, range_px)`, `Sfx.ui(...)`, `Sfx.has/pick/at_any`. `stream(id)` nimmt `.mp3`, sonst `.wav`.
- Danach `Godot --headless --import` ausführen (neue Dateien).

## Modelle
- `seed_audio` (Gratis-Testphase bis 2026-11-13, `use_unlim: true`): Sprachmodell, 2-5 s, **nur ein Job gleichzeitig** (parallel = 429), Wartezeit zuletzt ca. 7 min pro Sound.
- `mirelo_text_to_audio`: nicht von der Testphase gedeckt, nur über Credits. Drei Clips kamen so durch (`tree_fall`, `blink_in`, `map_open`) und liegen als **rohe mp3** vor (nicht auf Pegel gebracht, nicht getrimmt).

## Update (nach der Pause)
- `item_take` ist fertig (jetzt 24 Sounds), die drei mp3 (`tree_fall`, `blink_in`, `map_open`) sind zu wavs konvertiert (`sfx_process.py` liest mp3 über `pip install miniaudio`), die mp3 aus `assets/audio/sfx/` entfernt.
- `sfx_process.py` kann jetzt: mp3-Eingang, `loop: true` (mittlerer Ausschnitt, gleichmäßige Überblendung Ende -> Anfang) und `packs` (ein Clip mit mehreren Sounds, an den Stillen zerschnitten, spart Wartezeit).
- Manifest enthält jetzt alle Welle-2-Sounds und die Packs mit fertigen Prompts. **Nur noch nicht erzeugt.**
- **Blocker:** `generate_audio` mit `use_unlim: true` wird aus Claude Code jetzt abgelehnt ("unlimited generations are not available ... Claude chat, Claude Cowork, ChatGPT"). Credits: 0. Weiter geht es nur in Claude chat/Cowork oder mit neuen Credits (ca. 0,2 Credits pro Clip).

## Fertig und eingebunden (23, Stand vor der Pause)
Wav verarbeitet: sword_swing_a, sword_swing_b, sword_hit, blink_out, ellie_hurt_a, ellie_hurt_b, spider_attack, spider_grapple, spider_hurt, spider_death, axe_chop, pick_rock, rock_break, sickle_cut, pluck, eat_bite, drop_pop, item_pickup, coin_pickup, inv_open, inv_close.
Roh als mp3 (ohne Pegelangleichung): tree_fall, blink_in, map_open.

Haken im Code (Quellen): attack_component, blink_component, shadow_spider, player (ellie_hurt), tree/rock/bush/pebble, item_drop, eat_effect, progress_component (coin), UI: item_slot, inventory_window, hotbar, map_window, build_mode, pause_menu, main_menu_ui.

## Läuft noch (Gratis-Warteschlange)
- `item_take`: Job `611d46a6-6829-4e33-a07f-6556abf5e541` ist abgeschickt. Ergebnis über `jobs_wait` abholen, nach `sfx_raw/item_take.wav`, dann `sfx_process.py ... item_take`.

## Noch offen: Sounds, die im Manifest stehen
- UI / Bauen: item_put, equip, hotbar_select, ui_click, ui_confirm, ui_back, map_close, build_place, build_demolish
- Spinne: spider_notice

## Noch offen: noch nicht im Manifest (Welle 2)
- Boss: bear_roar
- Tiere: rabbit_thump, deer_call, fox_bark, badger_grunt, hedgehog_snuffle, bear_growl, bee_buzz, cricket_night
- Ambiente / Schleifen: wind_day_loop, wind_night_loop, river_loop, fire_crackle_loop (das Gratis-Modell ist dafür vermutlich schwach; Vorschlag: Mirelo mit Credits)
- Laufen: leaves_walk

## Noch offen: Technik
- Manifest um Welle 2 erweitern, Feld `loop` (Schleifen: nicht kürzen, Überblendung am Ende) in `sfx_process.py` einbauen.
- Die drei mp3s auf Pegel bringen (Konverter nötig, kein ffmpeg; oder per Gratis-Modell neu als wav erzeugen).
- Haken fehlen: `ui_back`, Tiere (woodland_mammal, bear, tiny_wildlife), Wind (TimeManager/WorldWind), Fluss (nahe Wasser), Feuer (HutYard/Lagerfeuer), Laub (Büsche).
- Einmal im Spiel anhören und Pegel/Längen prüfen; derzeit blockiert ein Parse-Fehler in `inventory_component.gd` (aus einer anderen Sitzung) den Spielstart.
- Optional: 2. und 3. Variante für häufige Sounds (Axt, Spitzhacke, Aufheben, Klick, Spinnentreffer).

## Stand nach dem Einarbeiten (2026-11-10)
- Rohclips: `tools/sfx_download.ps1` lädt sie nach `tools/sfx_raw/`, `py -3 tools/sfx_process.py tools/sfx_raw` verarbeitet alles, danach `--import`.
- Der Generator liefert Grundrauschen statt echter Stille zwischen den Sounds eines Packs. `split_clip` sucht deshalb Schwelle und Lückenlänge, bis genau so viele Stücke entstehen wie Ids. Alle 10 Packs gehen auf.
- **Eingebunden (neu):** Krähe/Rabe/Eule/Wiedehopf-Rufe (`wild_corvid.gd`, `CALL_SFX`, Rückfall auf die alten Platzhalter), Flügelschlag beim Abheben und Landen auf Ästen, Reh/Fuchs/Dachs/Igel/Bär (`woodland_mammal.gd`, `VOICES`, selten, 6 s Pause pro Tier, Jungbären stumm), Kaninchen-Klopfen auf der Flucht, Bienensummen, Wind Tag/Nacht und Grillen als Schichten in `DayAmbience`, Lagerfeuer-Schleife im HutYard (ersetzt `fire.wav`), `ui_back` beim Schließen des Pausenmenüs. `Sfx.loop(id)` macht Schleifen.
- **Unbrauchbar:** `river_loop` (Rohclip nur 0,55 s, als Schleife hörbar). Neu erzeugen, am besten länger oder mit anderem Prompt. Datei wurde aus dem Spiel entfernt.
- **Verarbeitet, aber ohne Haken:** `item_put`, `equip`, `leaves_walk`, `build_*`/`ui_confirm`/`map_close` (teils schon da, prüfen), Fluss-Schleife (fehlt), `spider_notice` (Haken war schon da).
- **Offen:** alles einmal anhören (Pegel, Längen, ob ein Clip Sprache oder Musik enthält), 2./3. Varianten für häufige Sounds.
