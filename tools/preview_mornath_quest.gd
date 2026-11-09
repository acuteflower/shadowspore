extends Node
## Captures the arena's quest props in the real world (needs graphics: `Godot --rendering-driver opengl3 --path . --fixed-fps 60 tools/preview_mornath_quest.tscn -- --dir=/abs/folder [--night]`):
## the dead knight at the east pillar (quest running), his dissolving, the hologram of Mornath in the middle (quest finished). Offline, no save is read or written.

var _dir: String = ""
var _night: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
		elif arg == "--night":
			_night = true
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	for i: int in 3:
		await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.health.floor_value = 1.0
	var story: ArenaStory
	for child: Node in world.get_children():
		if child is ArenaStory:
			story = child as ArenaStory
	if _night:
		TimeManager.set_time(0.95)
	player.global_position = story.knight.global_position + Vector2(-6, 70)
	for i: int in 150:
		await get_tree().process_frame
	await _shot("0_before_quest")
	world.debug_mornath(player, false)
	player.quests.set_flag("mornath_arena_reached")
	for i: int in 60:
		await get_tree().process_frame
	await _shot("1_knight")
	player.global_position = story.knight.global_position + Vector2(-2, 22)
	for i: int in 40:
		await get_tree().process_frame
	await _shot("2_knight_close")
	story.knight.dissolve()
	for i: int in 70:
		await get_tree().process_frame
	await _shot("3_dissolve_a")
	for i: int in 110:
		await get_tree().process_frame
	await _shot("4_dissolve_b")
	story.set_physics_process(false) ## the quest still runs: keep the story from hiding it again
	story.hologram.set_active(true)
	player.global_position = story.hologram.global_position + Vector2(-4, 64)
	for i: int in 20:
		await get_tree().process_frame
	await _shot("5_hologram_appear")
	for i: int in 150:
		await get_tree().process_frame
	await _shot("6_hologram")
	var img: Image = story.hologram._viewport.get_texture().get_image() ## where the bird really is in the picture (the viewport is 220 x 170, its middle is 110, 85)
	var used: Rect2i = img.get_used_rect()
	print("hologram picture: used ", used, " middle ", used.get_center())
	story.hologram.touched()
	for i: int in 25:
		await get_tree().process_frame
	await _shot("7_hologram_touched")
	get_tree().quit(0)
