class_name QuestBoardWindow
extends BoardWindow
## The quest board of the town (docs/questtafel_konzept.md): two tabs, AUSHANG (the notices that hang and that this player has not taken) and ANGENOMMEN (the ones they took and
## have not handed in). The look is `BoardWindow`'s; the host decides everything (`BoardManager.request_accept / request_finish`).

var board: BoardManager
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
	var ids: Array[int] = town.built_ids_of_role("board")
	var nearest: Vector2 = player.global_position
	var best: float = INF
	for id: int in ids:
		var middle: Vector2 = town.rect_of(id).get_center()
		if middle.distance_to(player.global_position) < best:
			best = middle.distance_to(player.global_position)
			nearest = middle
	focus_world = nearest
	board.changed.connect(_on_town_changed)
	board.result.connect(_on_notice)
	player.inventory.changed.connect(_on_town_changed)


func _exit_tree() -> void:
	if board != null:
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
	return "KEINE ZETTEL ANGENOMMEN" if _kind() == "mine" else "HEUTE HÄNGT NICHTS AM BRETT"


func _hint() -> String:
	return "W S WÄHLEN   A D REITER   E %s   ESC ZURÜCK" % ("ABGEBEN" if _kind() == "mine" else "ANNEHMEN")


func _giver_name(offer: Dictionary) -> String:
	var spec: Dictionary = town.settler_spec(String(offer.g))
	return String(spec.get("name", String(offer.g).to_upper()))


func _row(offer: Dictionary, running: bool) -> Dictionary:
	var kind: String = String(offer.k)
	var left: int = BoardRules.days_left(offer, TimeManager.day)
	var story: bool = kind == BoardRules.STORY
	var item: String = String(offer.t) if kind == BoardRules.FETCH else ("sword_basic" if kind == BoardRules.KILL else "")
	var row: Dictionary = {
		"kind": "notice", "id": int(offer.id), "offer": offer, "item": item, "count": 1,
		"name": String(offer.ti) if story else BoardRules.goal_text(offer),
		"sub": "VON %s" % _giver_name(offer), "state": OK, "why": "",
		"tag": "SIEGEL" if story else ("NOCH %d T" % left if left >= 0 else ""), "tag_color": GOLD if story else DIM,
	}
	if running:
		var entry: Dictionary = board.entry_of(int(offer.id), _peer)
		var have: int = board.have_of(offer, player)
		var got: int = BoardRules.progress(offer, entry, have)
		var ready: bool = BoardRules.can_finish(offer, entry, have)
		row["sub"] = "%d/%d  VON %s" % [got, int(offer.n), _giver_name(offer)]
		row["bar"] = float(got) / maxf(float(offer.n), 1.0)
		row["tag"] = "ABGEBEN" if ready else ("NOCH %d T" % left if left >= 0 else "")
		row["tag_color"] = LIT if ready else DIM
		row["state"] = OK if ready else MISSING
		row["why"] = "NOCH NICHT GENUG" if kind == BoardRules.FETCH else "NOCH NICHT ERLEDIGT"
		row["have"] = have
	return row


func _rebuild() -> void:
	rows.clear()
	if tabs.is_empty() or board == null:
		return
	if _kind() == "mine":
		for offer: Dictionary in board.running_for(_peer):
			rows.append(_row(offer, true))
	else:
		for offer: Dictionary in board.open_for(_peer):
			rows.append(_row(offer, false))
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String((a.offer as Dictionary).k) == BoardRules.STORY and String((b.offer as Dictionary).k) != BoardRules.STORY)


func _detail(area: Rect2, row: Dictionary) -> void:
	var offer: Dictionary = row.offer as Dictionary
	var kind: String = String(offer.k)
	draw_cell(area.position + Vector2(0, 2), String(row.item), int(offer.n) if kind == BoardRules.FETCH else 1, true, false)
	var x: float = area.position.x + 46.0
	_text(Vector2(x, area.position.y + 4.0), "%s" % _giver_name(offer), GOLD)
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
	else:
		var entry: Dictionary = board.entry_of(int(offer.id), _peer)
		var got: String = "%d/%d" % [BoardRules.progress(offer, entry, 0), int(offer.n)] if not entry.is_empty() else "0/%d" % int(offer.n)
		_text(Vector2(cx, cy), "ERLEGT " + got, TEXT)
		cx += float(PixelText.width("ERLEGT " + got)) + 10.0
	_text(Vector2(area.position.x, cy + 14.0), "LOHN", GOLD)
	var lx: float = area.position.x + 30.0
	draw_purse_left(lx, cy + 14.0, int(offer.c))
	lx += purse_width(int(offer.c)) + 6.0
	var extras: String = "%d XP" % int(offer.x)
	if int(offer.tr) > 0:
		extras += "  +%d VERTRAUEN" % int(offer.tr)
	_text(Vector2(lx, cy + 14.0), extras, LIT)
	var bonus: Dictionary = offer.get("b", {}) as Dictionary
	if not bonus.is_empty():
		draw_chip(Vector2(area.end.x - 60.0, cy + 10.0), String(bonus.id), int(bonus.n), int(bonus.n))


func _buttons() -> Array[Dictionary]:
	var row: Dictionary = _focused()
	if row.is_empty():
		return []
	if _kind() == "mine":
		return [{"id": "finish", "label": "ABGEBEN", "ready": int(row.state) == OK}]
	return [{"id": "accept", "label": "ANNEHMEN", "ready": true}]


func _press(id: String, _bulk: bool) -> void:
	var row: Dictionary = _focused()
	if row.is_empty():
		return
	match id:
		"accept":
			board.request_accept(int(row.id))
			_sound("page")
		"finish":
			board.request_finish(int(row.id))
			_sound("coin")
