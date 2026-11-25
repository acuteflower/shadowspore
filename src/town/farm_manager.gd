class_name FarmManager
extends Node
## The state of the town's fields (docs/farming.md): which cell of which field is hoed, watered, planted and how far the crop has grown. One child of the
## `TownManager` (`town.farm`), created in the same place on every peer so the RPCs find each other. The host decides (tool blows, planting, picking, the night's
## growth), everyone mirrors; the whole table travels in the town's snapshot (`export_state` / `import_state`) and is saved with it.
## Rules without nodes: `FarmRules`. The pictures: `FarmField` (soil) and `FieldCell` (one bed: crop, hurtbox, E).

signal cell_changed(field_id: int, index: int, fx: String) ## a cell has a new state on this peer (fx: till, water, scrape, plant, harvest, grow, "")
signal reset ## the whole table was replaced (load, snapshot)

const REACH: float = 64.0 ## how far from a cell's middle the one who works it may stand (matches expanded hoe/can reach)
const PLANT_REACH: float = 56.0
const WATER_REFILL_REACH: float = 52.0 ## px: fountain stand, rain barrel or water bank
const RAIN_REFILL_MIN: float = 0.25 ## outdoors rain strength that lets an upward/air swing catch rainwater

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
	if fx == "water":
		if not player.inventory.spend_water():
			town._tell(source, "GIESSKANNE LEER", false)
			return
	_rpc_cell.rpc(field_id, index, result.cell, fx)


## Local player asks the host to refill an unfull watering can from a nearby source (fountain, barrel, river/lake or rain).
func request_refill() -> void:
	if multiplayer.is_server():
		_host_refill(multiplayer.get_unique_id())
	else:
		_rpc_refill.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_refill() -> void:
	if multiplayer.is_server():
		_host_refill(multiplayer.get_remote_sender_id())


func _host_refill(peer: int, aim_dir: Vector2 = Vector2.ZERO) -> bool:
	var player: Player = _player(peer)
	if player == null or player.health.current <= 0.0:
		return false
	if not has_unfull_can(player):
		return false
	if not can_refill_at(player, aim_dir):
		return false
	if not player.inventory.refill_water():
		return false
	_rpc_refill_fx.rpc(player.global_position + Vector2(0.0, -8.0))
	return true


## Host only: swinging the watering can near a water source or outdoors in the rain fills it back up.
func host_swing_refill(player: Player, aim_dir: Vector2) -> bool:
	if not multiplayer.is_server() or player == null:
		return false
	return _host_refill(player.get_multiplayer_authority(), aim_dir)


static func has_unfull_can(player: Player) -> bool:
	if player == null or player.inventory == null:
		return false
	for stack: Variant in player.inventory.slots:
		var dict: Dictionary = stack as Dictionary
		var limit: int = Items.water_max(dict)
		if limit > 0 and Items.water(dict) < limit:
			return true
	return false


func can_refill_at(player: Player, aim_dir: Vector2 = Vector2.ZERO) -> bool:
	if player == null:
		return false
	var pos: Vector2 = player.global_position
	var tree: SceneTree = get_tree()
	## 1. Built Brunnenplatz fountain stand
	for id: int in town.built_ids("plaza"):
		if pos.distance_to(town.position_of(id)) <= WATER_REFILL_REACH + 10.0:
			return true
	## 2. Hut yard rain barrel
	if tree != null:
		for node: Node in tree.get_nodes_in_group("water_barrels"):
			var spot: Node2D = node as Node2D
			if spot != null and is_instance_valid(spot) and pos.distance_to(spot.global_position) <= WATER_REFILL_REACH:
				return true
	## 3. Rivers, ponds or lakes (foot or a short reach ahead)
	var probe: Vector2 = pos + aim_dir.normalized() * 18.0 if aim_dir.length_squared() > 0.01 else pos + player.facing * 18.0
	if town.world != null and town.world.has_method("water_depth"):
		if town.world.water_depth(pos) >= 0.0 or town.world.water_depth(probe) >= 0.0:
			return true
	## 4. Outdoors while it is raining
	var indoors: bool = Interiors.slot_at(pos) >= 0 or MineManager.in_mine(pos)
	if not indoors and WeatherManager.rain_now() >= RAIN_REFILL_MIN:
		return true
	return false


@rpc("authority", "call_local", "reliable")
func _rpc_refill_fx(at: Vector2) -> void:
	var parent: Node = town.get_parent() if town != null and town.get_parent() != null else self
	if parent == null or not is_inside_tree():
		return
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.one_shot = true
	puff.emitting = true
	puff.amount = 14
	puff.lifetime = 0.55
	puff.explosiveness = 0.92
	puff.direction = Vector2.UP
	puff.spread = 80.0
	puff.gravity = Vector2(0.0, 110.0)
	puff.initial_velocity_min = 18.0
	puff.initial_velocity_max = 42.0
	puff.scale_amount_min = 1.1
	puff.scale_amount_max = 1.8
	puff.color = Color("64d8f5")
	puff.global_position = at
	puff.z_index = 6
	parent.add_child(puff)
	get_tree().create_timer(1.0).timeout.connect(puff.queue_free)
	if ResourceLoader.exists("res://assets/audio/farming/can_pour.wav"):
		var audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		audio.stream = load("res://assets/audio/farming/can_pour.wav") as AudioStream
		audio.global_position = at
		audio.volume_db = -8.0
		parent.add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)


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
	for key: Variant in data:
		if not (data[key] is Dictionary):
			continue
		var cells: Dictionary = data[key] as Dictionary
		var table: Dictionary = {}
		for cell_key: Variant in cells:
			if not (cells[cell_key] is Dictionary):
				continue
			var raw: Dictionary = cells[cell_key] as Dictionary
			var state: Dictionary = {}
			for field_key: Variant in raw:
				var fk: String = String(field_key)
				if fk == "c":
					state[fk] = String(raw[field_key])
				else:
					state[fk] = int(raw[field_key])
			if not state.is_empty():
				table[int(cell_key)] = state
		if not table.is_empty():
			fields[int(key)] = table
	reset.emit()
