extends Node
## Ellie with the three first talismans on, in all eight facings (walking and standing), in a real arena.
## `Godot --rendering-driver opengl3 --path . tools/preview_talismans.tscn -- --capture=/abs/folder [--sword] [--only=silver_chain,wuchtreif,schweigtropfen]`; offline, no save.
const ARENA: PackedScene = preload("res://src/world/test_level.tscn")

class EmptyArena:
	extends TestLevel
	func _spawn_player(_id: int) -> void:
		pass
	func _fill_ground() -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--" + name:
			return "1"
		if arg.begins_with("--" + name + "="):
			return arg.trim_prefix("--" + name + "=")
	return fallback


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _run() -> void:
	var dir: String = _arg("capture", "")
	var arena: TestLevel = ARENA.instantiate() as TestLevel
	arena.set_script(EmptyArena)
	add_child(arena)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	arena.get_node("Players").add_child(player)
	player.global_position = Vector2(0, 0)
	player.progress.claimed = 25
	var ids: PackedStringArray = _arg("only", "silver_chain,wuchtreif,schweigtropfen").split(",")
	var slot: int = 1
	for id: String in ids:
		player.inventory.equipment["talisman_%d" % slot] = {"id": id, "count": 1}
		slot += 1
	if _arg("sword", "") != "":
		player.inventory.equipment["main_hand"] = {"id": "sword_iron", "count": 1}
	player.inventory.changed.emit()
	await _frames(20)
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	for facing: int in 8:
		player.facing = Vector2.from_angle(float(facing) * PI / 4.0)
		await _frames(8)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("facing_%d.png" % facing))
	get_tree().quit()
