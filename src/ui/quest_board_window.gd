class_name QuestBoardWindow
extends BoardWindow
## The quest board of the town (docs/questtafel_konzept.md): two tabs, AUSHANG (the notices that hang and that this player has not taken) and ANGENOMMEN (the ones they took and
## have not reported yet; the report itself is made to the giver, see `Settler.interact`). The look is `BoardWindow`'s; the host decides everything (`BoardManager.request_accept`).

const RUSH: Color = Color("e0788a") ## a rush notice (clock, tag)
const MARK: Color = Color("d640c8") ## a wanted poster (the magenta of the shadow creatures)
const NEED_WORDS: Dictionary = {"done": "AUFTRÄGE", "kills": "ERLEGT", "rush": "EILZETTEL", "bounty": "GEZEICHNETE", "givers": "BEWOHNER GEHOLFEN"}

var board: BoardManager
var tracked: TrackedQuests
var _peer: int = 0


static func open(tree: SceneTree, for_player: Player, for_town: TownManager, _at: Vector2 = Vector2.INF) -> QuestBoardWindow:
	if tree.get_first_node_in_group("board_window") != null or for_town.board == null:
		return null
	var window: QuestBoardWindow = QuestBoardWindow.new()
	tree.root.add_child(window)
	window.setup_board(for_player, for_town)
	return window


func _setup_board() -> void:
	add_to_group("quest_board_window")
	board = town.board
	_peer = player.name.to_int()
	title = "AUSHANG"
	tabs.append({"id": "board", "name": "AUSHANG", "kind": "board"})
	tabs.append({"id": "mine", "name": "ANGENOMMEN", "kind": "mine"})
	tabs.append({"id": "honor", "name": "EHRENTAFEL", "kind": "honor"})
	var ids: Array[int] = town.built_ids_of_role("board")
	var nearest: Vector2 = player.global_position
	var best: float = INF
	for id: int in ids:
		var middle: Vector2 = town.rect_of(id).get_center()
		if middle.distance_to(player.global_position) < best:
			best = middle.distance_to(player.global_position)
			nearest = middle
	focus_world = nearest
	tracked = player.tracked
	_read_all()
	board.changed.connect(_on_town_changed)
	board.changed.connect(_read_all)
	board.result.connect(_on_notice)
	player.inventory.changed.connect(_on_town_changed)
	if tracked != null:
		tracked.changed.connect(_on_town_changed)


## Looking at the board reads everything that hangs there: the bud on the board calms down.
func _read_all() -> void:
	if tracked == null:
		return
	var ids: Array = []
	for offer: Dictionary in board.hanging():
		ids.append(int(offer.id))
	tracked.mark_seen(ids)


func _exit_tree() -> void:
	if tracked != null and tracked.changed.is_connected(_on_town_changed):
		tracked.changed.disconnect(_on_town_changed)
	if board != null:
		if board.changed.is_connected(_read_all):
			board.changed.disconnect(_read_all)
		if board.changed.is_connected(_on_town_changed):
			board.changed.disconnect(_on_town_changed)
		if board.result.is_connected(_on_notice):
			board.result.disconnect(_on_notice)
	super._exit_tree()


func _kind() -> String:
	return String(tabs[tab].kind) if not tabs.is_empty() else ""


func _subtitle() -> String:
	return "%s  %d ZETTEL" % [town.town_name(), board.open_for(_peer).size() + board.running_for(_peer).size()]


func _header_right(right: float, y: float) -> void:
	draw_purse(right, y, player.progress.copper)


func _empty_text() -> String:
	return "KEINE ZETTEL ANGENOMMEN" if _kind() == "mine" else ("NOCH NICHTS ERLEDIGT" if _kind() == "honor" else "HEUTE HÄNGT NICHTS AM BRETT")


func _hint() -> String:
	if _kind() == "honor":
		return "W S WÄHLEN   A D REITER   E TITEL TRAGEN   ESC ZURÜCK"
	return "W S WÄHLEN   A D REITER   E VERFOLGEN   ESC ZURÜCK" if _kind() == "mine" else "W S WÄHLEN   A D REITER   E ANNEHMEN   ESC ZURÜCK"


func _giver_name(offer: Dictionary) -> String:
	if not town.has_met(String(offer.g)):
		return "UNBEKANNT" ## a name the player has not learned yet is not shown
	var spec: Dictionary = town.settler_spec(String(offer.g))
	return String(spec.get("name", String(offer.g).to_upper()))


func _row(offer: Dictionary, running: bool) -> Dictionary:
	var kind: String = String(offer.k)
	var left: int = BoardRules.days_left(offer, TimeManager.day)
	if running:
		left = BoardRules.entry_days_left(offer, board.entry_of(int(offer.id), _peer), TimeManager.day) ## a notice they carry has its own deadline
	var story: bool = kind == BoardRules.STORY
	var item: String = String(offer.t) if kind == BoardRules.FETCH else ("sword_basic" if kind == BoardRules.KILL else "")
	if BoardRules.is_bounty(offer):
		item = String((offer.get("b", {}) as Dictionary).get("id", "void_slag"))
	var row: Dictionary = {
		"kind": "notice", "id": int(offer.id), "offer": offer, "item": item, "count": 1,
		"name": String(offer.ti) if story else BoardRules.goal_text(offer),
		"sub": "VON %s" % _giver_name(offer), "state": OK, "why": "",
		"tag": "SIEGEL" if story else ("NOCH %d T" % left if left >= 0 else ""), "tag_color": GOLD if story else DIM,
	}
	if BoardRules.is_urgent(offer): ## a rush notice counts hours, not days
		row["tag"] = "EIL %d H" % BoardRules.urgent_hours(offer, TimeManager.time_of_day)
		row["tag_color"] = RUSH
	if BoardRules.is_bounty(offer):
		row["tag"] = "GESUCHT"
		row["tag_color"] = MARK
	if running:
		var entry: Dictionary = board.entry_of(int(offer.id), _peer)
		var have: int = board.have_of(offer, player)
		var got: int = BoardRules.progress(offer, entry, have)
		var ready: bool = BoardRules.can_finish(offer, entry, have)
		row["sub"] = "%d/%d  VON %s" % [got, int(offer.n), _giver_name(offer)]
		row["bar"] = float(got) / maxf(float(offer.n), 1.0)
		row["tag"] = "MELDEN" if ready else ("NOCH %d T" % left if left >= 0 else "")
		row["tag_color"] = LIT if ready else DIM
		if BoardRules.is_urgent(offer) and not ready:
			row["tag"] = "EIL %d H" % BoardRules.urgent_hours(offer, TimeManager.time_of_day)
			row["tag_color"] = RUSH
		if BoardRules.is_bounty(offer) and not ready:
			row["tag"] = "GESUCHT"
			row["tag_color"] = MARK
			row["sub"] = "VON %s  ZÄHLT, WENN DU IHN TRIFFST" % _giver_name(offer)
		row["state"] = OK if ready else MISSING
		row["why"] = "NOCH NICHT GENUG" if kind == BoardRules.FETCH else "NOCH NICHT ERLEDIGT"
		row["have"] = have
	return row


func _rebuild() -> void:
	rows.clear()
	if tabs.is_empty() or board == null:
		return
	if _kind() == "honor":
		_rebuild_honor()
		return
	if _kind() == "mine":
		for offer: Dictionary in board.running_for(_peer):
			rows.append(_row(offer, true))
	else:
		for offer: Dictionary in board.open_for(_peer):
			rows.append(_row(offer, false))
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String((a.offer as Dictionary).k) == BoardRules.STORY and String((b.offer as Dictionary).k) != BoardRules.STORY)


## The honour board: the titles (earned ones can be worn, the others show how far they are), then the names of the marked ones that fell.
func _rebuild_honor() -> void:
	var stats: Dictionary = board.stats_of(_peer)
	var worn: String = String((board.honor.titles as Dictionary).get(str(_peer), ""))
	for raw: Variant in BoardRules.titles():
		var title: Dictionary = raw as Dictionary
		var pair: Vector2i = BoardRules.title_progress(stats, title)
		var earned: bool = pair.x >= pair.y
		var key: String = String((title.need as Dictionary).keys()[0])
		var id: String = String(title.id)
		rows.append({
			"kind": "title", "id": id, "item": "", "count": 1, "name": String(title.name),
			"sub": "%d/%d %s" % [mini(pair.x, pair.y), pair.y, String(NEED_WORDS.get(key, ""))], "state": OK if earned else MISSING,
			"tag": "GETRAGEN" if worn == id else ("FREI" if earned else ""), "tag_color": GOLD if worn == id else LIT,
			"bar": clampf(float(pair.x) / float(maxi(pair.y, 1)), 0.0, 1.0), "earned": earned, "worn": worn == id,
		})
	for rec: Variant in board.honor.fallen as Array:
		var fallen: Dictionary = rec as Dictionary
		rows.append({
			"kind": "fallen", "id": "fallen", "item": "void_slag", "count": 1, "name": String(fallen.name),
			"sub": "TAG %d  NACH %d NÄCHTEN" % [int(fallen.day), int(fallen.nights)], "state": OK, "tag": "GEFALLEN", "tag_color": MARK,
		})


func _detail_honor(area: Rect2, row: Dictionary) -> void:
	var mine: Dictionary = board.stats_of(_peer)
	var town_stats: Dictionary = board.stats_of(0)
	var done: int = int(town_stats.get("done", 0))
	var y: float = area.position.y + 2.0
	_text(Vector2(area.position.x, y), "%d AUFTRÄGE ERLEDIGT" % done, GOLD)
	var steps: Array = BoardRules.honor_cfg().get("milestones", []) as Array
	for step: Variant in steps:
		if done < int(step):
			_text(Vector2(area.end.x - float(PixelText.width("NÄCHSTE: %d" % int(step))), y), "NÄCHSTE: %d" % int(step), DIM)
			break
	y += 12.0
	_text(Vector2(area.position.x, y), "DU %d   BESCHAFFT %d   ERLEGT %d" % [int(mine.get("done", 0)), int(mine.get("fetch", 0)), int(mine.get("kills", 0))], TEXT)
	y += 10.0
	_text(Vector2(area.position.x, y), "EILIG %d   GEZEICHNETE %d   BEWOHNER %d" % [int(mine.get("rush", 0)), int(mine.get("bounty", 0)), BoardRules.stat_value(mine, "givers")], TEXT)
	y += 14.0
	if String(row.kind) == "title":
		_text(Vector2(area.position.x, y), "NUR ZUR ZIERDE: ER STEHT IN DER STADTSEITE" if bool(row.earned) else "NOCH NICHT VERDIENT", LIT if bool(row.earned) else DIM)
	else:
		_text(Vector2(area.position.x, y), "SEIN NAME BLEIBT AN DER TAFEL", MARK)


func _detail(area: Rect2, row: Dictionary) -> void:
	if _kind() == "honor":
		_detail_honor(area, row)
		return
	var offer: Dictionary = row.offer as Dictionary
	var kind: String = String(offer.k)
	draw_cell(area.position + Vector2(0, 2), String(row.item), int(offer.n) if kind == BoardRules.FETCH else 1, true, false)
	var x: float = area.position.x + 46.0
	_text(Vector2(x, area.position.y + 4.0), "%s" % _giver_name(offer), GOLD)
	var why: String = String(offer.get("w", ""))
	if why != "": ## the occasion: the small proof that the town reacts
		_text(Vector2(x + float(PixelText.width(_giver_name(offer))) + 8.0, area.position.y + 4.0), why, RUSH if BoardRules.is_urgent(offer) else LIT)
	if _kind() == "mine" and tracked != null: ## whether the notice is in the quest branch and on the map
		var follow: String = "IM FOKUS" if tracked.is_tracked(int(offer.id)) else "OFFEN"
		_text(Vector2(area.end.x - float(PixelText.width(follow)), area.position.y + 4.0), follow, LIT if tracked.is_tracked(int(offer.id)) else DIM)
	elif BoardRules.is_urgent(offer):
		var clock: String = "NUR NOCH %d H" % BoardRules.urgent_hours(offer, TimeManager.time_of_day)
		_text(Vector2(area.end.x - float(PixelText.width(clock)), area.position.y + 4.0), clock, RUSH)
	var y: float = area.position.y + 16.0
	for line: String in _wrap(String(offer.txt), int(area.size.x) - 52).slice(0, 3):
		_text(Vector2(x, y), line, DIM)
		y += 9.0
	if kind == BoardRules.STORY:
		_text(Vector2(area.position.x, area.position.y + 46.0), "NIMM DEN ZETTEL, UM ZU BEGINNEN", GOLD)
		return
	var cy: float = area.position.y + 46.0
	var cx: float = area.position.x
	if kind == BoardRules.FETCH:
		cx += draw_chip(Vector2(cx, cy - 4.0), String(offer.t), board.have_of(offer, player), int(offer.n))
	elif BoardRules.is_bounty(offer):
		_text(Vector2(cx, cy), "%d NÄCHTE ÜBERLEBT   ZÄHLT FÜR JEDEN, DER IHN TRIFFT" % int(offer.get("bh", 1)), MARK)
	else:
		var entry: Dictionary = board.entry_of(int(offer.id), _peer)
		var got: String = "%d/%d" % [BoardRules.progress(offer, entry, 0), int(offer.n)] if not entry.is_empty() else "0/%d" % int(offer.n)
		_text(Vector2(cx, cy), "ERLEGT " + got, TEXT)
		cx += float(PixelText.width("ERLEGT " + got)) + 10.0
		if String(offer.get("win", "")) == "night":
			_text(Vector2(cx, cy), "NUR BEI NACHT", GOLD)
	_text(Vector2(area.position.x, cy + 14.0), "LOHN", GOLD)
	var lx: float = area.position.x + 30.0
	draw_purse_left(lx, cy + 14.0, int(offer.c))
	lx += purse_width(int(offer.c)) + 6.0
	var extras: String = "%d XP" % int(offer.x)
	if int(offer.tr) > 0:
		extras += "  +%d VERTRAUEN" % int(offer.tr)
	_text(Vector2(lx, cy + 14.0), extras, LIT)
	if BoardRules.is_urgent(offer):
		_text(Vector2(area.position.x, cy + 26.0), "EILZETTEL: BIS ZUR DÄMMERUNG, DOPPELTER LOHN", RUSH)
	var bonus: Dictionary = offer.get("b", {}) as Dictionary
	if not bonus.is_empty():
		draw_chip(Vector2(area.end.x - 60.0, cy + 10.0), String(bonus.id), int(bonus.n), int(bonus.n))


func _buttons() -> Array[Dictionary]:
	var row: Dictionary = _focused()
	if row.is_empty():
		return []
	if _kind() == "honor":
		if String(row.kind) != "title":
			return []
		return [{"id": "wear", "label": "ABLEGEN" if bool(row.worn) else "TRAGEN", "ready": bool(row.earned)}]
	if _kind() == "mine":
		var follows: bool = tracked != null and tracked.is_tracked(int(row.id)) ## reporting is done at the settler who gave the notice, not here
		return [{"id": "track", "label": "FOKUS LÖSEN" if follows else "FOKUSSIEREN", "ready": tracked != null}]
	return [{"id": "accept", "label": "ANNEHMEN", "ready": true}]


func _press(id: String, _bulk: bool) -> void:
	var row: Dictionary = _focused()
	if row.is_empty():
		return
	match id:
		"wear":
			board.request_title("" if bool(row.worn) else String(row.id))
			_sound("page")
		"accept":
			board.request_accept(int(row.id))
			_sound("page")
		"track":
			if tracked != null:
				tracked.toggle_track(int(row.id))
				_sound("page")
