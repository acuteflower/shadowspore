extends Node
## The witch's tower standing in the real Hexenwald (it is not placed in the world yet).
## Godot --rendering-driver opengl3 --path . tools/preview_witch_tower.tscn -- --dir=/abs/folder [--at=x,y]
## Writes day.png, night.png, witch.png (she passes the window) and anim_00..11.png (a second and a half of the night, for a look at the motion).
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
func _ready() -> void: _run.call_deferred()
func _shot(dir: String, name_: String) -> void:
	await RenderingServer.frame_post_draw
	if not dir.is_empty(): get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name_])
func _run() -> void:
	var dir: String = ""
	var tile: Vector2 = Vector2(826, 880)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=")
		if arg.begins_with("--at="):
			var parts: PackedStringArray = arg.trim_prefix("--at=").split(",")
			tile = Vector2(float(parts[0]), float(parts[1]))
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	add_child(world)
	var hero: Player = world._players.get_child(0) as Player
	hero.request_teleport(tile * 16.0 + Vector2(34, 30))
	hero.get_node("OpeningGuide").set_process(false)
	hero.quests.set_physics_process(false)
	hero.quests.set_flag("mist_hint_seen")
	hero.health.floor_value = hero.health.max_health
	hero.health.current = hero.health.max_health
	hero.sync_wound_visuals()
	hero.get_node("Hud").visible = false if hero.has_node("Hud") else false
	var tower: WitchTower = WitchTower.new()
	tower.position = tile * 16.0
	hero.get_parent().add_child(tower)
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(0, -150)
	tower.add_child(camera)
	camera.make_current()
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.5
	for i: int in 200: await get_tree().process_frame
	await _shot(dir, "day")
	TimeManager.time_of_day = 0.0
	for i: int in 120: await get_tree().process_frame
	await _shot(dir, "night")
	tower.walk_now()
	for i: int in 70: await get_tree().process_frame
	await _shot(dir, "witch")
	for k: int in 12:
		for i: int in 7: await get_tree().process_frame
		await _shot(dir, "anim_%02d" % k)
	get_tree().quit()
