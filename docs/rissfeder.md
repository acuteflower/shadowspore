# Die Rissfeder (legendäre Kette, Beute von Mornath)

Stand 2026-11-10, **vollständig eingebaut**. Vierter Talisman (nach Silberkette, Wuchtreif, Schweigtropfen, siehe `docs/talisman_konzept.md`) und der erste mit **Sonderfähigkeiten** (`perks`) und einer **Bossbeute pro Spieler**. Alle Texte sind Platzhalter.

## Idee

Mornath, der Himmelsspalter (`boss_sky_cleaver`, `docs/boss_sky_cleaver.md`), ist ein Rabenwesen, das den Himmel selbst aufreißt. Die Rissfeder ist eine **Schwungfeder, die der Himmel nicht halten konnte**: blauschwarz, die Kiele von einem violetten Riss gespalten, an einer Kette aus Rabenstahl. Wer sie trägt, "fällt nie ganz": ein tödlicher Treffer reißt die Luft auf. Dazu passt alles andere an ihr: Blinzeln (Leere) ist schneller, nach dem Blinzeln stürzt man wie ein Raubvogel herab, und Krähen und Raben nehmen die Trägerin für eine der Ihren.

Gattung **Kette (Körper)**, Seltenheit **legendär**. Die Kette ist die einzige offene Gattung mit nur einem gewöhnlichen Stück: die Rissfeder ist dort eine echte Entscheidung gegen die Silberkette (eine je Gattung, `TalismanRules.conflict`).

## Werte (`data/items.json` `rissfeder`)

| Wirkung | Wert |
|---|---|
| Leben | +20 |
| Rüstung | +3 |
| Blinzelpause (`blink_cooldown`) | -30 % (`BlinkComponent.start_cooldown`, die Anzeige `BlinkIcon` richtet sich nach `total`) |
| Krähengunst (`corvid_calm`) | 70 %: wilde Krähen und Raben (`WildCorvid`) werden erst bei viel größerer Nähe/Lärm unruhig (Alarm- und Fluchtreichweite x 0.3) |

### Sonderfähigkeiten (`data/talismans.json` `perks`, in der Karte unter den Werten)

- **LETZTER FLÜGELSCHLAG** (`ward`): ein Treffer (oder Tick), der sie töten würde, wird abgefangen. Sie bleibt mit **30 %** ihres maximalen Lebens stehen, ist **2,5 s unverwundbar**, die Feder zerplatzt in einem Federnschwarm (`FeatherBurst`, Riss in der Luft, Ring am Boden, Kamerarütteln, Klang `ward`) und stößt Gegner im Radius von 72 px zurück (12 Schaden, Rückstoß 260). Danach **240 s Pause**; in dieser Zeit ist der Stein auf der Brust grau und still (`TalismanArt` `dull`), wenn sie wieder bereit ist, klingt `ward_ready` und er glimmt wieder. Gilt nicht für `kill()` (Urteile, Skript) und nicht für `take_survivable`.
- **STURZFLUG** (`dive`): nach jedem Blinzeln trifft der **nächste Waffenschlag** innerhalb von 3 s mit **+40 %** Schaden (`AttackComponent._hit_scan` x `TalismanComponent.dive_factor()`, verbraucht erst, wenn ein Schlag wirklich trifft).

## Beute (Mornath)

`data/enemies.json` `boss_sky_cleaver.loot.relics = [{"id": "rissfeder", "first": 1.0, "chance": 0.1}]`.

- **Erster Sieg: 100 %. Jeder weitere: 10 %.** Gezählt **pro Spielerin** (`BossRelics`, Knoten des `WorldLevel`, Gruppe `boss_relics`): jede lebende Gewinnerin würfelt für sich, und die Feder ist **ihr eigener Drop** (`ItemDrop.story_owner`, `story_id` `relic:rissfeder`, läuft nie ab, verschmilzt nicht). So verliert in einer Gruppe niemand den sicheren ersten Drop an eine schnellere Hand.
- **Gespeichert** (`SaveGame` `relics`): die Siege je Spielerin und die noch nicht aufgehobenen Federn mit Ort. Wer vor dem Aufheben beendet, verliert nichts; die Feder liegt nach dem Laden wieder da und wird nicht doppelt erzeugt.
- `DropComponent._roll` ruft `BossRelics.roll(...)` auf, wenn der Beutetext `relics` hat. Weitere Bosse brauchen nur denselben Eintrag.
- Entwicklermenü ENTWICKLER: **RISSFEDER BEKOMMEN** (nur sie, in die Tasche), **ALLE TALISMANE** legt sie in die Tasche, **MORNATH: ERSTER KILL** vergisst alle Siege (der nächste zählt wieder als erster).

## Aussehen

- Icon: `rissfeder()` in `py -3 tools/art_talismans.py` -> `assets/items/rissfeder.png`.
- An Ellie: Metall `ravensteel` (`TalismanArt.METALS`, blauschwarz mit violettem Schimmer), eine Feder mit Riss als Anhänger (`look.pendant`), pulsierender Stein. Ohne bereiten Flügelschlag (`ward_ready` false) ist der Stein grau und still. Vorschau: `tools/preview_talismans.tscn -- --capture=/abs/folder --only=rissfeder`, Karte: `tools/preview_talisman_card.tscn`.
- Karte (`ItemTooltip`): Sonderfähigkeiten als eigene Zeilen (Federknospe, Name, umbrochener Text) unter den Werten.
- Klänge `py -3 tools/audio_talisman.py`: `equip_ravensteel`, `ward`, `ward_ready` (angehängt, die älteren Klänge bleiben bitgleich).

## Technik in Kürze

- Regeln rein in `TalismanRules`: `perks`, `perk_ids`, `perk_text`, `perk_name`, `blink_scale`, `corvid_calm`; neue Werte `blink_cooldown`, `corvid_calm` in `talismans.json` (`lower_better` für Werte, bei denen weniger besser ist, auch `alarm`).
- `TalismanComponent` hält `perks`, `ward_ready`, `dive_left`; die Entscheidungen fallen auf dem Host (`_ward_check`, `spend_dive`), alle Peers spielen `_ward_state` / `_dive_end` (RPC, nur vom Host) nach.
- `HealthComponent.ward` (Callable, nur Host) wird von `take_damage` und `take_tick` gefragt, bevor ein tödlicher Wert gesendet wird.

## Federbund mit dem Himmelsriss
Das Schwert `sword_rift` (`docs/rissklinge.md`) wird aus einer Rissfeder geschmiedet; trägt sie die Feder um den Hals, verkürzt jeder vom Himmelskreuz (zweiter Rechtsklick-Hieb) getroffene Gegner die Pause des Letzten Flügelschlags um 8 s, höchstens 32 s je Hieb (`TalismanComponent.shorten_ward`).

## Grenzen

- Die Siege zählt die Peer-ID (Einzelspiel immer 1). Wer in einer Mehrspielerrunde unter einer anderen ID wieder eintritt, zählt als neue Spielerin.
- Die Pause des Flügelschlags wird nicht gespeichert (nach dem Laden ist er bereit); ein später Beitretender sieht ihn als bereit.
- Karte und Stein auf Ellie kennen nur einen bereiten/gebrauchten Zustand, keine Restzeit.

## Tests

`tools/test_talismans.tscn` (Regeln, Werte, Schutz einmalig, Pause, Tick, Blinzelpause, Sturzflug, Beuteliste inkl. Speichern/Laden, 10 % über 400 Würfe) und die Kartenvorschau.
