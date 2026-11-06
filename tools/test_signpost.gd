extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var post: Signpost = world.get_node("Signpost_crossroad") as Signpost
	var ok: bool = true
	player.quests.start("find_help")
	player.quests.import_data({"active": {"find_help": 9}, "active_steps": {"find_help": "sign"}})
	post.interact(player)
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	ok = ok and box.is_active() and not player.quests.has_flag("read_sign")
	box._end()
	ok = ok and player.quests.has_flag("read_sign")
	print("SIGNPOST: ", "ok" if ok else "FAILED")
	get_tree().quit(0 if ok else 1)
