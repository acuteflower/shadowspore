class_name TrackedQuests
extends Node
## The one list of everything the local player is working on, for the quest branch of the HUD (`QuestVine`) and the map (`MapWindow`): the story quest (`QuestComponent`) first,
## then every quest-board notice they took and have not handed in (docs/questtafel_ausbau_konzept.md 3.1). A taken notice is a quest from the moment it is taken.
## This is the seam for the quest rework: HUD and map only know this list, so a new quest system only has to feed it. An entry is a Dictionary in the shape of
## `QuestComponent.current()` plus {id "story:<quest>" | "board:<notice id>", source, kind "story" | "fetch" | "kill", oid (notice id), have, need, ready, giver, giver_name, days_left, label,
## urgent + urgent_left (a rush notice and the share of its clock left), why (the occasion chip), window ("night"), area (Vector3 px x y radius or INF) + area_name}.
## Also holds what only this player knows about the board: which notices they have read (`seen`, the bud on the board pulses for unread ones) and which they do not follow (`untracked`).
## Child of the owner's Player (like `QuestComponent`); nothing here is replicated.

signal changed ## the list or what it shows may have changed
signal finished(id: String) ## a board entry was handed in (the branch flares)
signal lapsed(id: String) ## a board entry ran out or vanished

const MAX_SHOWN: int = 4 ## the branch shows the main entry and up to three twigs

var quests: QuestComponent
var seen: Dictionary = {} ## notice id (int) -> true
var untracked: Dictionary = {} ## notice id (int) -> true: taken, but not shown in the branch and on the map
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
		quests.changed.connect(_emit_changed)
	if player.inventory != null:
		player.inventory.changed.connect(_emit_changed)
	TimeManager.day_started.connect(_on_day)


func _exit_tree() -> void:
	if TimeManager.day_started.is_connected(_on_day):
		TimeManager.day_started.disconnect(_on_day)


func _process(delta: float) -> void:
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
	_note_departures()
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
		else:
			lapsed.emit("board:%d" % id)
	_running = now


## Forget notices that are gone from the board for good.
func _prune() -> void:
	if _board == null or not _board.is_ready():
		return
	for table: Dictionary in [seen, untracked]:
		for id: int in table.keys():
			if _board.offer_of(id).is_empty():
				table.erase(id)


# ---------- the list ----------

## Everything the player works on, the story quest first, then the board notices (soonest deadline first). Untracked notices are left out.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if quests != null:
		var now: Dictionary = quests.current()
		if not now.is_empty():
			now["source"] = "story"
			now["kind"] = "story"
			now["id"] = "story:%s" % String(now.id)
			out.append(now)
	out.append_array(board_entries(false))
	return out


## The notices the player took and has not handed in, as entries. `with_untracked` also lists the ones they do not follow (the window).
func board_entries(with_untracked: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _board == null or _player == null:
		return out
	var peer: int = _peer()
	for offer: Dictionary in _board.running_for(peer):
		if untracked.has(int(offer.id)) and not with_untracked:
			continue
		out.append(_entry_of(offer, peer))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: int = int(a.days_left) if int(a.days_left) >= 0 else 9999
		var db: int = int(b.days_left) if int(b.days_left) >= 0 else 9999
		return da < db or (da == db and int(a.oid) < int(b.oid)))
	return out


func _entry_of(offer: Dictionary, peer: int) -> Dictionary:
	var entry: Dictionary = _board.entry_of(int(offer.id), peer)
	var have: int = _board.have_of(offer, _player)
	var got: int = BoardRules.progress(offer, entry, have)
	var ready: bool = BoardRules.can_finish(offer, entry, have)
	var giver: String = String(offer.g)
	var spec: Dictionary = _board.town.settler_spec(giver)
	var giver_name: String = String(spec.get("name", giver.to_upper()))
	var kind: String = String(offer.k)
	var what: String = BoardRules.item_name(String(offer.t)) if kind == BoardRules.FETCH else BoardRules.species_name(String(offer.t))
	if BoardRules.is_bounty(offer):
		what = String(offer.bn) ## a marked one is known by its name
	var target: Vector2 = Vector2.INF
	if ready: ## the goal is the one who gave it: the marker follows them wherever they walk
		var node: Node2D = _board.town.person_node(giver)
		if node != null and node.is_inside_tree():
			target = node.global_position
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
	return {
		"area": area, "area_name": area_name, "urgent": BoardRules.is_urgent(offer), "urgent_left": BoardRules.urgent_left(offer, TimeManager.time_of_day),
		"why": String(offer.get("w", "")), "window": String(offer.get("win", "")), "bounty": BoardRules.is_bounty(offer),
		"id": "board:%d" % int(offer.id), "source": "board", "kind": kind, "oid": int(offer.id),
		"title": BoardRules.goal_text(offer),
		"text": ("MELDE DICH BEI %s." % giver_name) if ready else String(offer.txt),
		"step": 0, "steps": 1, "target": target, "search": 0.0, "hint": "",
		"tasks": [{"text": what, "done": ready, "have": got, "need": int(offer.n), "counter": true}],
		"have": got, "need": int(offer.n), "ready": ready,
		"giver": giver, "giver_name": giver_name,
		"days_left": BoardRules.entry_days_left(offer, entry, TimeManager.day),
		"label": what,
	}


# ---------- tracking ----------

func is_tracked(oid: int) -> bool:
	return not untracked.has(oid)


func toggle_track(oid: int) -> void:
	if untracked.has(oid):
		untracked.erase(oid)
	else:
		untracked[oid] = true
	changed.emit()


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

func export_data() -> Dictionary:
	return {"seen": seen.keys(), "untracked": untracked.keys()}


func import_data(data: Dictionary) -> void:
	seen.clear()
	for id: Variant in data.get("seen", []) as Array:
		seen[int(id)] = true
	untracked.clear()
	for id: Variant in data.get("untracked", []) as Array:
		untracked[int(id)] = true
	changed.emit()
