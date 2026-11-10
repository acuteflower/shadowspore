# Questtafel (Aushang der Stadt)

Stand: 2026-11-10. Entschieden mit dem Nutzer; Texte sind Platzhalter für den Dialog-Autor.

## 1. Idee

Die Questtafel ist ein Stadtstück (`quest_board`, Rolle `board`). Auf ihr hängen Zettel:

- **Siedler-Zettel** (`fetch`, `kill`): kleine Wünsche von Bewohnern ("Bring mir 12 Holz", "Vertreib zwei Schattenspinnen"). Neue Zettel erscheinen mit jedem Sonnenaufgang, alte verfallen nach 3-5 Tagen.
- **Story-Zettel** (`story`): ein besonderer, gesiegelter Zettel, der hängen bleibt, bis man ihn annimmt. Die Annahme startet die Story-Quest (`quests.start(id)`), danach läuft sie wie bisher (Dialog, Szenen, HUD-Ast).

## 2. Entscheidungen

| Frage | Antwort |
|---|---|
| Koop | Aushänge sind gemeinsam (der Host würfelt sie, alle sehen dieselben). Jeder Spieler nimmt jeden Zettel für sich an und bekommt seine eigene Belohnung. Ein Zettel ist pro Spieler einmal erledigbar. |
| Auftragsarten | Beschaffen und abgeben (auch Fische und seltene Pflanzen), Jagen (Schattenwesen), die Fang-/Ernte-Wünsche sind `fetch` mit seltenen Zielen. Bauen/Stadtwünsche: nicht in Version 1. |
| Belohnung | Kupfer und XP (immer), Vertrauen beim Auftraggeber, optional ein Gegenstand (Chance, siehe `bonus`). Rezept-Belohnungen: später über `TownManager.unlock`. |
| Story | Gesiegelter Zettel, Annahme startet die Quest. Bedingung pro Zettel (`after`: Quest fertig, `flag`: Spieler-Flag), geprüft am Host-Spieler. |

## 3. Ablauf

1. Das Stück braucht keinen Bewohner. Es steht im Lichtgebiet und ist fertig gebaut, dann gilt es als Tafel.
2. **Host, bei jedem Sonnenaufgang** (`TimeManager.day_started`): abgelaufene Zettel verschwinden, dann würfelt `BoardRules.roll` bis zu `new_per_day` neue (Chance `post.chance`), solange weniger als `limits.simple` Siedler-Zettel hängen. Ein Bewohner hat höchstens `per_giver` offene Zettel. Nur Bewohner (`TownManager.residents`) geben Zettel aus, `min_day` und `min_trust` der Vorlage beschränken.
3. **Annehmen** (E an der Tafel, im Fenster): der Host trägt den Spieler ein (`taken[id][peer]`), bei Story-Zetteln startet er die Quest beim Besitzer.
4. **Fortschritt**: `fetch` zählt die Tasche des Spielers (Anzeige 7/12), `kill` zählt Tode, die der Spieler als Letzter verursacht (`DropComponent._roll` ruft `BoardManager.note_kill`), nur nach dem Annehmen.
5. **Abgeben** (E an der Tafel, Knopf ABGEBEN/ABHOLEN, innerhalb `reach` der Tafel): der Host prüft, nimmt die Ware, zahlt aus (`ProgressComponent.award`, Vertrauen, Gegenstand) und markiert den Zettel für diesen Spieler als erledigt. Für andere hängt er weiter bis zum Ablauf.

## 4. Daten (`data/board.json`)

```
piece, reach (px um die Tafel zum Abgeben), limits {simple, per_giver, new_per_day},
post {chance}, lifetime [min_tage, max_tage],
templates [{id, kind "fetch"|"kill", givers [ids] (leer = jeder Bewohner), item | species, count [min, max],
            copper_each [min, max], xp_each, trust, min_day, min_trust, bonus {id, n, chance}, text}]
story [{id, quest, giver, title, text, after, flag}]
```
`text` kennt `{count}` und `{item}` / `{species}`; Platzhalter für den Dialog-Autor.

## 5. Netzwerk und Speichern

Der Host hält die Wahrheit (`BoardManager`, Kind von `TownManager`, Knoten `Board`), jeder Peer eine Kopie.
- Client → Host: `_rpc_accept(id)`, `_rpc_finish(id)`.
- Host → alle: `_rpc_state(offers, taken)` (gesamt, selten), `_rpc_result(peer, id, text, ok)` für die Rückmeldung, `_rpc_start_quest(quest)` an den Besitzer.
- Gespeichert wird in `town.board` (`offers`, `taken` mit den Schlüsseln des Host-Spielers `"1"`, `next_id`, `posted_story`). Beigetretene Mitspieler behalten ihre angenommenen Zettel nur für die laufende Sitzung (Peer-ID ist nicht stabil).

## 5a. Aushang von außen sichtbar

Das gebaute Brett zeigt seine Zettel direkt in der Welt (`BoardNotes`, zwei Kind-Knoten der `TownStructure`: Papier im Weltlicht, Siegel ungeschattet darüber). Sechs Plätze auf der leeren Tafel, Story-Zettel zuerst. Gold mit glimmendem teal Siegel = Story, helles Papier = Beschaffen, Papier mit rotem Fleck = Jagd; ein neuer Zettel fällt an seinen Platz, einer, den der lokale Spieler schon angenommen oder erledigt hat, hängt verblasst. Das Bild `quest_board.png` ist absichtlich leer (nur Nagelköpfe). Vorschau: `tools/preview_quest_board.tscn -- --capture=/abs.png [--night]`.

## 6. Fenster (`QuestBoardWindow`, Unterklasse von `BoardWindow`)

Reiter: AUSHANG (alle Zettel, die man noch nicht erledigt hat; Story-Zettel oben mit Siegel), ANGENOMMEN (laufende mit Fortschritt). Detail: Auftraggeber, Text, Ware/Fortschritt, Belohnungschips, Restzeit. Knöpfe: ANNEHMEN, ABGEBEN.

## 7. Nicht gebaut / offen

- Eigene Tafel-Grafik (aktuell Platzhalter, `py -3 tools/art_quest_board.py`), Siedler-Zettelfiguren, Ton.
- Welche der bestehenden Story-Quests (zum Beispiel die Folge nach der Einführung) künftig über die Tafel laufen: Eintrag in `story`, bisher ein Beispiel.
- Bau-/Stadtwünsche, Rezept-Belohnungen, gemeinsame Gruppenaufträge, Auftragskette eines Siedlers.
- Mitspieler-Zuordnung über Sitzungen hinweg.

Tests: `tools/test_board.tscn` (druckt `BOARD OK`).
