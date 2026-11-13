extends Node
## Look study of the star mirror in the trials' test world: the pond by day, the reflection at night (full moon), Ellie carrying a stone, stones
## lying right with light between them, the solved mirror.
## Run: Godot --rendering-driver opengl3 --path . tools/preview_star_mirror.tscn -- --dir=/abs/folder [--id=stars_rabe]

var _dir: String = ""
var _id: String = "stars_sichel"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--id="):
			_id = a.get_slice("=", 1)
	_run.call_deferred()


func _wait(sec: float) -> void:
	var t: float = 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	if _dir != "":
		get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
		print("captured ", name)


func _carry(m: StarMirror, player: Player, i: int, to: Vector2) -> void:
	var stone: StarStone = m._stones[i]
	player.global_position = stone.global_position + Vector2(0, 14)
	await _wait(0.1)
	m.stone_used(stone, player)
	await _wait(0.9)
	player.global_position = to + Vector2(0, 14)
	await _wait(0.2)
	m._ask("drop", i, to)
	await _wait(0.9)


func _run() -> void:
	NetworkManager.host_singleplayer()
	var world: Node2D = (load("res://src/world/trial_level.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	await _wait(0.3)
	var m: StarMirror = Puzzles.of(get_tree()).trial(_id) as StarMirror
	var player: Player = (world.get("_players") as Node).get_child(0) as Player
	player.intro = null
	TimeManager.set_time(0.45)
	player.global_position = m._pond + Vector2(-20, 70)
	await _wait(1.0)
	await _shot("stars_1_day")
	TimeManager.day = 4
	TimeManager.set_time(TimeManager.NIGHT_START + 0.03)
	await _wait(1.0)
	await _shot("stars_2_night")
	var stone: StarStone = m._stones[0]
	player.global_position = stone.global_position + Vector2(0, 14)
	await _wait(0.2)
	m.stone_used(stone, player)
	await _wait(0.25)
	await _shot("stars_3_lift")
	await _wait(0.8)
	player.global_position = m.star_position(0) + Vector2(-14, 0)
	player.facing = Vector2.RIGHT
	await _wait(0.3)
	await _shot("stars_4_carry")
	m._ask("drop", 0, m.star_position(0))
	await _wait(1.2)
	for i: int in range(1, m.stars.size() - 1):
		await _carry(m, player, i, m.star_position(i))
	player.global_position = m._field + Vector2(0, m._size * 0.5 + 30)
	await _wait(0.6)
	await _shot("stars_5_almost")
	player.global_position = m._pond + Vector2(-30, 56)
	await _wait(0.4)
	await _shot("stars_5b_water")
	var last: int = m.stars.size() - 1
	await _carry(m, player, last, m.star_position(last))
	await _wait(1.0)
	await _shot("stars_6_solved")
	await _wait(3.5)
	await _shot("stars_7_chest")
	get_tree().quit()
