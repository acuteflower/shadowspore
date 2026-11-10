class_name FarmManager
extends Node
## The state of the town's fields (docs/farming.md): which cell of which field is hoed, watered, planted and how far the crop has grown. One child of the
## `TownManager` (`town.farm`), created in the same place on every peer so the RPCs find each other. The host decides (tool blows, planting, picking, the night's
## growth), everyone mirrors; the whole table travels in the town's snapshot (`export_state` / `import_state`) and is saved with it.
## Rules without nodes: `FarmRules`. The pictures: `FarmField` (soil) and `FieldCell` (one bed: crop, hurtbox, E).

signal cell_changed(field_id: int, index: int, fx: String) ## a cell has a new state on this peer (fx: till, water, scrape, plant, harvest, grow, "")
signal reset ## the whole table was replaced (load, snapshot)

const REACH: float = 52.0 ## how far from a cell's middle the one who works it may stand (the swing's fan reaches about 22 px from her chest)
const PLANT_REACH: float = 44.0

var town: TownManager
var fields: Dictionary = {} ## int field id -> {int cell index -> cell Dictionary (see FarmRules)}


func setup(owner_town: TownManager) -> void:
	town = owner_town
	if multiplayer.is_server():
		TimeManager.day_started.connect(_on_day_started)


func _exit_tree() -> void:
	if TimeManager.day_started.is_connected(_on_day_started):
		TimeManager.day_started.disconnect(_on_day_started)


# ---------- questions ----------

static func grid_of(piece: String) -> Vector2i:
	var foot: Array = TownRules.piece(piece).get("foot", [16, 16]) as Array
	return Vector2i(maxi(1, roundi(float(foot[0]) / float(FarmRules.CELL))), maxi(1, roundi(float(foot[1]) / float(FarmRules.CELL))))


func cell_state(field_id: int, index: int) -> Dictionary:
	return ((fields.get(field_id, {}) as Dictionary).get(index, {}) as Dictionary)


## The middle of a cell on the ground (global).
func cell_center(field_id: int, index: int) -> Vector2:
	if not town.structures.has(field_id):
		return Vector2.INF
	var data: Dictionary = town.structures[field_id] as Dictionary
	var grid: Vector2i = grid_of(String(data.p))
	var rect: Rect2 = TownRules.foot_rect(String(data.p), float(data.x), float(data.y))
	var at: Vector2i = FarmRules.cell_coords(index, grid.x)
	return rect.position + Vector2((float(at.x) + 0.5) * FarmRules.CELL, (float(at.y) + 0.5) * FarmRules.CELL)


## Counts for the town page / tests: {"beds", "planted", "ripe"} over all fields.
func tally() -> Dictionary:
	var out: Dictionary = {"beds": 0, "planted": 0, "ripe": 0}
	for field_id: Variant in fields:
		for cell: Variant in (fields[field_id] as Dictionary).values():
			var state: Dictionary = cell as Dictionary
			if bool(state.get("t", 0)):
				out.beds = int(out.beds) + 1
			if String(state.get("c", "")) != "":
				out.planted = int(out.planted) + 1
			if FarmRules.is_ripe(state):
				out.ripe = int(out.ripe) + 1
	return out


# ---------- the host decides ----------

func _player(peer: int) -> Player:
	return town.player_of(peer)


func _valid(field_id: int, index: int) -> bool:
	if not town.structures.has(field_id) or not town.is_built(field_id):
		return false
	var data: Dictionary = town.structures[field_id] as Dictionary
	if not bool(TownRules.piece(String(data.p)).get("farm", false)):
		return false
	var grid: Vector2i = grid_of(String(data.p))
	return index >= 0 and index < grid.x * grid.y


func _near(player: Player, field_id: int, index: int, reach: float) -> bool:
	return player != null and player.health.current > 0.0 and player.global_position.distance_to(cell_center(field_id, index)) <= reach


## A blow of the hoe or the watering can landed on a cell (`FieldCell.harvest_hit`, host only): whatever the tool in her hand does to it.
func host_hit(field_id: int, index: int, source: int) -> void:
	if not multiplayer.is_server() or not _valid(field_id, index):
		return
	var player: Player = _player(source)
	if player == null or not _near(player, field_id, index, REACH):
		return
	var tool_id: String = String(Items.definition(player.inventory.active_stack()).get("tool", ""))
	if tool_id != "hoe" and tool_id != "can":
		return
	var before: Dictionary = cell_state(field_id, index)
	var result: Dictionary = FarmRules.apply_tool(before, tool_id, TimeManager.day)
	var fx: String = String(result.fx)
	if fx == "":
		return
	_rpc_cell.rpc(field_id, index, result.cell, fx)


func request_plant(field_id: int, index: int) -> void:
	if multiplayer.is_server():
		_host_plant(field_id, index, multiplayer.get_unique_id())
	else:
		_rpc_plant.rpc_id(1, field_id, index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_plant(field_id: int, index: int) -> void:
	if multiplayer.is_server():
		_host_plant(field_id, index, multiplayer.get_remote_sender_id())


func _host_plant(field_id: int, index: int, peer: int) -> void:
	if not _valid(field_id, index):
		return
	var player: Player = _player(peer)
	if player == null or not _near(player, field_id, index, PLANT_REACH):
		return
	var seed_item: String = String((player.inventory.slots[player.inventory.selected] as Dictionary).get("id", "")) ## seeds are no tools: whatever lies in the selected hotbar slot
	var before: Dictionary = cell_state(field_id, index)
	var reason: String = FarmRules.plant_block(before, seed_item)
	if reason != "":
		town._tell(peer, reason, false)
		return
	if not player.inventory.remove_item(seed_item, 1):
		return
	_rpc_cell.rpc(field_id, index, FarmRules.plant(before, seed_item, TimeManager.day), "plant")


func request_harvest(field_id: int, index: int) -> void:
	if multiplayer.is_server():
		_host_harvest(field_id, index, multiplayer.get_unique_id())
	else:
		_rpc_harvest.rpc_id(1, field_id, index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_harvest(field_id: int, index: int) -> void:
	if multiplayer.is_server():
		_host_harvest(field_id, index, multiplayer.get_remote_sender_id())


func _host_harvest(field_id: int, index: int, peer: int) -> void:
	if not _valid(field_id, index):
		return
	var player: Player = _player(peer)
	if player == null or not _near(player, field_id, index, PLANT_REACH):
		return
	var before: Dictionary = cell_state(field_id, index)
	if not FarmRules.is_ripe(before):
		return
	var result: Dictionary = FarmRules.harvest(before, randf(), TimeManager.day)
	var at: Vector2 = cell_center(field_id, index)
	DropComponent.spawn_drops(get_tree(), result.drops as Array, at + Vector2(0.0, -6.0))
	_rpc_cell.rpc(field_id, index, result.cell, "harvest")
	if player.quests != null:
		player.quests.set_flag("harvested_" + String(before.get("c", "")))


## Every sunrise: the night's growth for every planted cell, watering dries (a rainy day waters everything again at once).
func _on_day_started(day: int) -> void:
	if not multiplayer.is_server():
		return
	var rain: bool = Moisture.is_wet_day(day)
	var changes: Dictionary = {}
	for field_id: int in fields.keys():
		var table: Dictionary = fields[field_id] as Dictionary
		var field_changes: Dictionary = {}
		for index: int in table.keys():
			var before: Dictionary = table[index] as Dictionary
			var next: Dictionary = FarmRules.sunrise(before, day, false)
			if rain and not next.is_empty() and bool(next.get("t", 0)):
				next["w"] = day + 1 ## it rains: the beds are dark and drink for tonight
			if next != before:
				field_changes[index] = next
		if not field_changes.is_empty():
			changes[field_id] = field_changes
	if not changes.is_empty():
		_rpc_day.rpc(changes)


@rpc("authority", "call_local", "reliable")
func _rpc_cell(field_id: int, index: int, state: Dictionary, fx: String) -> void:
	_set_cell(field_id, index, state)
	cell_changed.emit(field_id, index, fx)


@rpc("authority", "call_local", "reliable")
func _rpc_day(changes: Dictionary) -> void:
	for field_id: Variant in changes:
		var field_changes: Dictionary = changes[field_id] as Dictionary
		for index: Variant in field_changes:
			_set_cell(int(field_id), int(index), field_changes[index] as Dictionary)
			cell_changed.emit(int(field_id), int(index), "grow")


func _set_cell(field_id: int, index: int, state: Dictionary) -> void:
	if state.is_empty():
		if fields.has(field_id):
			(fields[field_id] as Dictionary).erase(index)
			if (fields[field_id] as Dictionary).is_empty():
				fields.erase(field_id)
		return
	if not fields.has(field_id):
		fields[field_id] = {}
	(fields[field_id] as Dictionary)[index] = state


## A field was taken down: its beds go with it (the seed in it is lost; demolishing asks for care).
func field_removed(field_id: int) -> void:
	fields.erase(field_id)
	reset.emit()


# ---------- saving ----------

func export_state() -> Dictionary:
	var out: Dictionary = {}
	for field_id: int in fields:
		var cells: Dictionary = {}
		for index: int in fields[field_id] as Dictionary:
			cells[str(index)] = ((fields[field_id] as Dictionary)[index] as Dictionary).duplicate()
		out[str(field_id)] = cells
	return out


func import_state(data: Dictionary) -> void:
	fields.clear()
	for key: String in data:
		var cells: Dictionary = data[key] as Dictionary
		var table: Dictionary = {}
		for cell_key: String in cells:
			var raw: Dictionary = cells[cell_key] as Dictionary
			var state: Dictionary = {}
			for field_key: String in raw:
				if field_key == "c":
					state[field_key] = String(raw[field_key])
				else:
					state[field_key] = int(raw[field_key])
			if not state.is_empty():
				table[int(cell_key)] = state
		if not table.is_empty():
			fields[int(key)] = table
	reset.emit()
