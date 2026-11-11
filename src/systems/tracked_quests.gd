class_name TrackedQuests
extends Node
## The local journal's view of story and accepted board quests. The HUD and map read its single focus.

signal changed ## the list or what it shows may have changed
signal finished(id: String) ## a board entry was handed in (the branch flares)

const COOP_JOURNALS: String = "user://coop_journals.cfg"

var quests: QuestComponent
var seen: Dictionary = {} ## notice id (int) -> true
var journal_page: String = "":
	set(value):
		if journal_page != value:
			journal_page = value
			_queue_guest_save()
var journal_archive: bool = false:
	set(value):
		if journal_archive != value:
			journal_archive = value
			_queue_guest_save()
var journal_opened: bool = false:
	set(value):
		if journal_opened != value:
			journal_opened = value
			_queue_guest_save()
var _focus: String = ""
var _focus_cleared: bool = false
var _guest_world: String = ""
var _guest_save_left: float = -1.0
var _player: Player
var _board: BoardManager
var _running: Dictionary = {} ## notice id -> true: what was running at the last refresh (to tell handed in from vanished)
var _poll: float = 0.0
var _clock_tick: float = 0.0


func setup(player: Player, own_quests: QuestComponent) -> void:
	_player = player
	quests = own_quests
	process_mode = Node.PROCESS_MODE_ALWAYS
	if quests != null:
		if not multiplayer.is_server():
			quests.set_flag("hud_unlocked") ## the host plays the opening, a guest already has access to their journal
		quests.changed.connect(_on_story_changed)
		quests.quest_finished.connect(_on_story_finished)
	if player.inventory != null:
		player.inventory.changed.connect(_emit_changed)
	TimeManager.day_started.connect(_on_day)
	_on_story_changed()


func _exit_tree() -> void:
	_save_guest_journal()
	if TimeManager.day_started.is_connected(_on_day):
		TimeManager.day_started.disconnect(_on_day)


func _process(delta: float) -> void:
	if _guest_save_left >= 0.0:
		_guest_save_left -= delta
		if _guest_save_left < 0.0:
			_save_guest_journal()
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.5
	_clock_tick -= 0.5
	if _clock_tick <= 0.0:
		_clock_tick = 4.0
		_process_clock()
	var board: BoardManager = _find_board()
	if board != _board:
		if _board != null and is_instance_valid(_board) and _board.changed.is_connected(_on_board):
			_board.changed.disconnect(_on_board)
		_board = board
		if _board != null:
			_board.changed.connect(_on_board)
			_on_board()


func _find_board() -> BoardManager:
	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
	return town.board if town != null else null


func board() -> BoardManager:
	return _board


func _peer() -> int:
	return _player.name.to_int() if _player != null else 0


func _emit_changed() -> void:
	changed.emit()


func _on_story_changed() -> void:
	if _focus == "" and not _focus_cleared:
		_focus = _first_story_id()
	_queue_guest_save()
	changed.emit()


func _on_story_finished(id: String) -> void:
	if _focus != "story:%s" % id:
		return
	var next: String = quests.next_quest(id)
	_focus = "story:%s" % next if next != "" and not quests.is_finished(next) else _first_story_id()


func _first_story_id() -> String:
	if quests != null:
		var active: Array[String] = quests.active_ids()
		if not active.is_empty():
			return "story:%s" % active[0]
	return ""


func _on_day(_day: int) -> void:
	_prune()
	changed.emit()


## The clock of a rush notice moves on: the ring in the branch follows (a few times a minute is enough).
func _process_clock() -> void:
	if _board == null:
		return
	for offer: Dictionary in _board.running_for(_peer()):
		if BoardRules.is_urgent(offer):
			changed.emit()
			return


func _on_board() -> void:
	_load_guest_journal()
	_note_departures()
	if _focus.begins_with("board:") and _board.is_ready() and active_entry(_focus).is_empty():
		_focus = _first_story_id()
		_queue_guest_save()
	changed.emit()


## What stood on the list and is gone now: handed in (the branch flares) or run out.
func _note_departures() -> void:
	if _board == null:
		return
	var now: Dictionary = {}
	for offer: Dictionary in _board.running_for(_peer()):
		now[int(offer.id)] = true
	for id: int in _running.keys():
		if now.has(id):
			continue
		if bool(_board.entry_of(id, _peer()).get("done", false)):
			finished.emit("board:%d" % id)
	_running = now


## Forget notices that are gone from the board for good.
func _prune() -> void:
	if _board == null or not _board.is_ready():
		return
	for id: int in seen.keys():
		if _board.offer_of(id).is_empty():
			seen.erase(id)


# ---------- the list ----------

func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if quests != null:
		for id: String in quests.active_ids():
			var row: Dictionary = _story_entry(id)
			_attach_story_memories(row, id, true)
			out.append(row)
	out.append_array(board_entries())
	return out


func _story_entry(id: String) -> Dictionary:
	var now: Dictionary = quests.active_entry(id)
	if not now.is_empty():
		now["id"] = "story:%s" % id
		now["source"] = "story"
	return now


func _attach_story_memories(row: Dictionary, id: String, include_previous: bool) -> void:
	var lines: Array[String] = []
	if include_previous:
		for previous: String in quests.finished_ids():
			var memory: String = String(DataRegistry.get_entry("quest_journal", previous).get("finished", ""))
			if memory != "":
				lines.append(memory)
	var notes: Dictionary = DataRegistry.get_entry("quest_journal", id)
	var milestones: Dictionary = notes.get("milestones", {})
	var completed: Array[String] = quests.completed_step_ids(id)
	for step: String in completed:
		var memory: String = String(milestones.get(step, ""))
		if memory != "":
			lines.append(memory)
	row["memories"] = lines.slice(maxi(0, lines.size() - 2))
	if completed.has(String(notes.get("sketch_after", ""))):
		row["sketch"] = String(notes.get("sketch", ""))


func archive_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if quests != null:
		var completed: Array[String] = quests.finished_ids()
		completed.reverse()
		for id: String in completed:
			var row: Dictionary = {"id": "story:%s" % id, "source": "story", "title": quests.quest_title(id), "status": "finished"}
			_attach_story_memories(row, id, false)
			out.append(row)
	if _board != null:
		var records: Array = _board.archived_for(_peer())
		for i: int in range(records.size() - 1, -1, -1):
			var row: Dictionary = (records[i] as Dictionary).duplicate()
			row["id"] = "board:%d:%d" % [int(row.oid), int(row.attempt)]
			row["source"] = "board"
			out.append(row)
	return out


func board_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _board == null or _player == null:
		return out
	var peer: int = _peer()
	for offer: Dictionary in _board.running_for(peer):
		out.append(_entry_of(offer, peer))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: int = int(a.days_left) if int(a.days_left) >= 0 else 9999
		var db: int = int(b.days_left) if int(b.days_left) >= 0 else 9999
		return da < db or (da == db and int(a.oid) < int(b.oid)))
	return out


static func deadline_text(entry: Dictionary) -> String:
	if bool(entry.get("urgent", false)):
		var minutes: int = roundi(float(entry.urgent_until) * 1440.0)
		return "Bis %02d:%02d Uhr" % [minutes / 60, minutes % 60]
	var due: int = int(entry.get("due", -1))
	return "Bis zum Morgen von Tag %d" % (due + 1) if due >= 0 else ""


func _entry_of(offer: Dictionary, peer: int) -> Dictionary:
	var entry: Dictionary = _board.entry_of(int(offer.id), peer)
	var have: int = _board.have_of(offer, _player)
	var got: int = BoardRules.progress(offer, entry, have)
	var ready: bool = BoardRules.can_finish(offer, entry, have)
	var giver: String = String(offer.g)
	var spec: Dictionary = _board.town.settler_spec(giver)
	var giver_name: String = String(spec.get("name", giver.to_upper())) if _board.town.has_met(giver) else "UNBEKANNT"
	var kind: String = String(offer.k)
	var what: String = BoardRules.item_name(String(offer.t)) if kind == BoardRules.FETCH else BoardRules.species_name(String(offer.t))
	if BoardRules.is_bounty(offer):
		what = String(offer.bn) ## a marked one is known by its name
	var target: Vector2 = Vector2.INF
	var target_actor: Node2D
	if ready: ## the goal is the one who gave it: the marker follows them wherever they walk
		target_actor = _board.town.person_node(giver)
		if target_actor != null and target_actor.is_inside_tree():
			target = target_actor.global_position
	var area: Vector3 = Vector3.INF ## where on the map to look, px (x, y, radius): the hunting ground of a report, or where the plant grows
	var area_name: String = ""
	if not ready:
		var at: Array = offer.get("a", []) as Array
		if at.size() == 3:
			area = Vector3(float(at[0]), float(at[1]), float(at[2]))
			area_name = "ZULETZT GESEHEN" if BoardRules.is_bounty(offer) else "EINSATZGEBIET"
		elif kind == BoardRules.FETCH:
			var hint: Dictionary = BoardRules.hint_of(String(offer.t))
			var zone: Array = hint.get("area", []) as Array
			if zone.size() == 3:
				area = Vector3(float(zone[0]), float(zone[1]), float(zone[2])) * 16.0
				area_name = String(hint.get("name", "FUNDGEBIET"))
	var bonus: Dictionary = offer.get("b", {})
	return {
		"area": area, "area_name": area_name, "urgent": BoardRules.is_urgent(offer), "urgent_left": BoardRules.urgent_left(offer, TimeManager.time_of_day),
		"why": String(offer.get("w", "")), "window": String(offer.get("win", "")), "bounty": BoardRules.is_bounty(offer),
		"id": "board:%d" % int(offer.id), "source": "board", "kind": kind, "oid": int(offer.id),
		"attempt": int(entry.get("attempt", 1)), "due": BoardRules.entry_due(offer, entry),
		"urgent_until": float(offer.get("ut", 0.0)), "reward": [int(offer.c), int(offer.x), int(offer.tr)],
		"reward_item": "%d %s" % [int(bonus.n), BoardRules.item_name(String(bonus.id))] if not bonus.is_empty() else "",
		"title": BoardRules.goal_text(offer),
		"text": ("MELDE DICH BEI %s." % giver_name) if ready else String(offer.txt),
		"notice": String(offer.txt),
		"step": 0, "steps": 1, "target": target, "target_actor": target_actor, "search": 0.0, "hint": "",
		"tasks": [{"text": what, "done": ready, "have": got, "need": int(offer.n), "counter": true}],
		"have": got, "need": int(offer.n), "ready": ready,
		"giver": giver, "giver_name": giver_name,
		"days_left": BoardRules.entry_days_left(offer, entry, TimeManager.day),
		"label": what,
	}


# ---------- tracking ----------

func active_entry(id: String) -> Dictionary:
	if id.begins_with("story:") and quests != null:
		return _story_entry(id.trim_prefix("story:"))
	if id.begins_with("board:") and _board != null:
		var oid: int = int(id.trim_prefix("board:"))
		var offer: Dictionary = _board.offer_of(oid)
		var entry: Dictionary = _board.entry_of(oid, _peer())
		if BoardRules.entry_active(offer, entry, TimeManager.day, TimeManager.time_of_day):
			return _entry_of(offer, _peer())
	return {}


func focused() -> Dictionary:
	if _focus_cleared:
		return {}
	var selected: Dictionary = active_entry(_focus)
	return selected if not selected.is_empty() else active_entry(_first_story_id())


func focus(id: String) -> void:
	if id != "" and active_entry(id).is_empty():
		return
	_focus = id
	_focus_cleared = id == ""
	_queue_guest_save()
	changed.emit()


func is_tracked(oid: int) -> bool:
	return _focus == "board:%d" % oid


func toggle_track(oid: int) -> void:
	focus("" if is_tracked(oid) else "board:%d" % oid)


# ---------- reading ----------

func is_seen(oid: int) -> bool:
	return seen.has(oid)


func mark_seen(ids: Array) -> void:
	var moved: bool = false
	for id: Variant in ids:
		if not seen.has(int(id)):
			seen[int(id)] = true
			moved = true
	if moved:
		_queue_guest_save()
		changed.emit()


## Notices that hang, that this player has not taken and has not read.
func unread() -> Array[int]:
	var out: Array[int] = []
	if _board == null or _player == null:
		return out
	var peer: int = _peer()
	for offer: Dictionary in _board.open_for(peer):
		if not seen.has(int(offer.id)):
			out.append(int(offer.id))
	return out


# ---------- saving ----------

func _load_guest_journal() -> void:
	var id: String = _board.world_id
	if multiplayer.is_server() or _guest_world == id or id.length() != 32 or not id.is_valid_hex_number():
		return
	_guest_world = id
	var file: ConfigFile = ConfigFile.new()
	if file.load(COOP_JOURNALS) == OK:
		if quests != null and file.has_section_key(id, "quests"):
			quests.import_data(file.get_value(id, "quests") as Dictionary)
			quests.set_flag("hud_unlocked")
		if file.has_section_key(id, "journal"):
			import_data(file.get_value(id, "journal") as Dictionary)
	if quests != null:
		for quest_id: String in _board.story_quests_for(_peer()):
			quests.start(quest_id)
	_queue_guest_save()


func _queue_guest_save() -> void:
	if _guest_world != "" and _guest_save_left < 0.0:
		_guest_save_left = 0.75


func _save_guest_journal() -> void:
	if _guest_world == "":
		return
	_guest_save_left = -1.0
	var file: ConfigFile = ConfigFile.new()
	file.load(COOP_JOURNALS)
	file.set_value(_guest_world, "journal", export_data())
	if is_instance_valid(quests):
		file.set_value(_guest_world, "quests", quests.export_data())
	file.save(COOP_JOURNALS)


func export_data() -> Dictionary:
	return {"seen": seen.keys(), "focus": _focus, "focus_cleared": _focus_cleared, "journal_page": journal_page, "journal_archive": journal_archive, "journal_opened": journal_opened}


func import_data(data: Dictionary) -> void:
	seen.clear()
	for id: Variant in data.get("seen", []) as Array:
		seen[int(id)] = true
	_focus = String(data.get("focus", ""))
	_focus_cleared = bool(data.get("focus_cleared", false))
	journal_page = String(data.get("journal_page", ""))
	journal_archive = bool(data.get("journal_archive", false))
	journal_opened = bool(data.get("journal_opened", journal_page != ""))
	_on_story_changed()
