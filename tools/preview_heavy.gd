extends Node
## Look study of the sword's heavy blow in a real arena: charge, hold, strike, recover.
## `Godot --rendering-driver opengl3 --path . tools/preview_heavy.tscn -- --capture=/abs/folder [--facing=0..7]`; offline, no save.
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
		if arg.begins_with("--" + name + "="):
			return arg.trim_prefix("--" + name + "=")
	return fallback


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _run() -> void:
	var dir: String = _arg("capture", "")
	var arena: TestLevel = ARENA.instantiate() as TestLevel
	arena.set_script(EmptyArena)
	add_child(arena)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	arena.get_node("Players").add_child(player)
	player.global_position = Vector2(0, 0)
	player.attack.held_weapon = "sword_iron"
	player.facing = Vector2.from_angle(float(_arg("facing", "0")) * PI / 4.0)
	await _frames(20)
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	Input.action_press("action_secondary")
	await _frames(6)
	await _shot(dir, "1_draw")
	await _frames(20)
	await _shot(dir, "2_drawn")
	await _frames(40)
	await _shot(dir, "3_full")
	Input.action_release("action_secondary")
	await _frames(5)
	await _shot(dir, "4_chop")
	await _frames(4)
	await _shot(dir, "5_impact")
	await _frames(14)
	await _shot(dir, "6_rebound")
	await _frames(30)
	await _shot(dir, "7_recover")
	get_tree().quit()
