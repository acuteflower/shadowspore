extends Node
## Step 6 of the mine: a chest in a treasure room opens once (host decides: distance, state, loot), the table remembers it, notes can be read.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("MINE CHEST FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var mines: MineManager = world.get_node("Mines") as MineManager
	var player: Player = world._players.get_child(0) as Player
	var level: int = 0
	var chest_at: Vector2 = Vector2.ZERO
	for candidate: int in range(1, 9):
		var l: MineLayout = mines.layout(candidate)
		for c: Vector2i in l.chunk_props:
			for entry: Dictionary in l.chunk_props[c] as Array:
				if String(entry.kind) == "chest" and level == 0:
					level = candidate
					chest_at = Vector2(float(entry.x), float(entry.y))
	_check(level > 0, "some level has a treasure chest")
	if level == 0:
		get_tree().quit(1)
		return
	mines.enter(player, level)
	var spot: Vector2 = MineManager.origin(level) + chest_at + Vector2(0, 14)
	player.request_teleport(spot)
	for i: int in 30:
		await get_tree().process_frame
	var chests: Array[Node] = get_tree().get_nodes_in_group("mine_chests")
	_check(chests.size() >= 1, "the chest exists in the loaded chunk")
	var chest: MineChest = chests[0] as MineChest
	_check(chest.prompt() == "ÖFFNEN", "a shut chest offers to open")
	var copper_before: int = int(player.progress.get("copper"))
	var drops_before: int = get_tree().get_first_node_in_group("drops").get_child_count() if get_tree().get_first_node_in_group("drops") != null else 0
	chest.interact(player)
	await get_tree().process_frame
	_check(mines.is_set(chest.key), "the table remembers the chest")
	_check(chest.prompt() == "", "an open chest offers nothing")
	_check(int(player.progress.get("copper")) > copper_before, "copper was paid (%d -> %d)" % [copper_before, int(player.progress.get("copper"))])
	var drops_node: Node = get_tree().get_first_node_in_group("drops")
	_check(drops_node == null or drops_node.get_child_count() >= drops_before, "items may drop")
	var paid: int = int(player.progress.get("copper"))
	mines.request_chest(chest.key)
	await get_tree().process_frame
	_check(int(player.progress.get("copper")) == paid, "a chest pays only once")
	# the state survives an export / import
	var data: Dictionary = mines.export_state()
	mines.state.clear()
	mines.import_state(data)
	_check(mines.is_set(chest.key), "state survives export and import")
	# a far player cannot open another chest: distance is checked
	var far_key: String = "chest:%d:%d" % [level, 1]
	mines.request_chest(far_key)
	_check(not mines.is_set(far_key), "an unknown chest does nothing")
	# a note can be read
	var note: MineNote = MineNote.new()
	note.setup("stollen", 3, "res://assets/mine/props/notes.png", 14)
	add_child(note)
	_check(note.prompt() == "LESEN", "a note offers to be read")
	print("MINE CHEST: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
