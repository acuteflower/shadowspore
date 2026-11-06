extends Node
## The developer checkpoint "FERTIGE STADT" (`WorldLevel.debug_jump_town`): the town stands finished, Gustav is at his bench, the quest waits for the meeting. Run with `--fixed-fps 60`.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TOWN JUMP FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	await _frames(60)
	world.debug_jump_town()
	await _frames(120)
	var quests: QuestComponent = player.quests
	_check(town.founded, "the town is founded")
	for piece: String in TownRules.buildable():
		_check(town.has_built(piece), "%s stands finished" % piece)
	_check(town.built_ids("lamp_post").size() >= 2, "two lamp posts")
	_check(town.residents.has("gustav") and town.settler_node("gustav") != null, "Gustav is there")
	_check(String(quests.current().get("step_id", "")) == "meet_stranger", "the quest waits at the meeting (%s)" % String(quests.current().get("step_id", "")))
	_check(quests.is_finished("rebuild_hut") and quests.is_finished("lumberjack") and quests.has_flag("built_workshop"), "the chapters before are done")
	_check(player.inventory.has_item("sickle_basic") and player.inventory.has_item("pickaxe_basic") and player.inventory.has_item("axe_basic"), "the tools are in the bag")
	var gustav: Settler = town.settler_node("gustav")
	player.request_teleport(gustav.global_position + Vector2(24, 10))
	await _frames(40)
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	_check(box != null and box.is_active() or quests.has_flag("gustav_joined") or String(quests.current().get("step_id", "")) == "gustav_hello", "walking up to him starts the talk (%s)" % String(quests.current().get("step_id", "")))
	print("TOWN JUMP: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
