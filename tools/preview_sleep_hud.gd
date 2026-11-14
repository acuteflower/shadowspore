extends Node
## Visual capture for the ClockVine Schlaf-Knospe (locked vs blooming), StatusTags (`well_rested` & `tired`),
## and the hut bed prompt (`"SCHLAFEN / DU BIST NOCH NICHT MÜDE"` vs unlocked `"SCHLAFEN"`).
## Run: godot --rendering-driver opengl3 --path . res://tools/preview_sleep_hud.tscn -- --dir=/abs/folder

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")


func _ready() -> void:
	_run.call_deferred()


func _shot(dir: String, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, file_name])


func _run() -> void:
	var dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
	GameCursor.visible = false
	NetworkManager.host_singleplayer()
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.opening_over = true
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var hero: Player = world._players.get_child(0) as Player
	hero.health.current = hero.health.max_health
	hero.quests.set_flag("hud_unlocked")
	var hud: CanvasLayer = hero.get("_hud") as CanvasLayer
	if hud != null and hud.has_method("open"):
		hud.call("open")
	await get_tree().create_timer(1.8).timeout
	TimeManager.unlock()
	TimeManager.sleep_fatigue = 0.0

	# Shot 1: Early night (before 70% threshold) + tired tier II
	TimeManager.set_time(0.92)
	hero.effects.apply("tired", 120.0, 2.0)
	for _i: int in 8:
		await get_tree().process_frame
	await _shot(dir, "sleep_hud_locked_tired")

	# Shot 2: After threshold (moonflower blooming) + well_rested
	TimeManager.set_time(0.09)
	hero.effects.clear("tired")
	hero.effects.apply("well_rested", 120.0, 1.0)
	for _i: int in 8:
		await get_tree().process_frame
	await _shot(dir, "sleep_hud_bloom_rested")
	get_tree().quit(0)
