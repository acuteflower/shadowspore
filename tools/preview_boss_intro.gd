extends Node
## Captures the boss entrance screen in the real arena (needs graphics: `Godot --rendering-driver opengl3 --path . --fixed-fps 60 tools/preview_boss_intro.tscn -- --dir=/abs/folder`).
## Saves a picture at fixed moments of the flight and of the name card; offline, no save is read or written.
const FLIGHT_SHOTS: Array[float] = [0.1, 0.3, 0.55, 0.9, 1.4, 2.0, 2.6]
const CARD_SHOTS: Array[float] = [0.05, 0.2, 0.4, 0.7, 1.2, 2.0, 3.2, 3.55, 3.85]

var _dir: String = ""
var _landed: float = -1.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_dir, name])


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	for i: int in 3:
		await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var spec: Dictionary = (DataRegistry.table("ground").get("arenas", []) as Array)[0] as Dictionary
	var tile: Array = spec.tile as Array
	var origin: Vector2 = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
	player.global_position = origin + Vector2(20, 240) ## just outside the floor (south, where the ramp is)
	for i: int in 120: ## let the chunks stream in
		await get_tree().process_frame
	await _shot("0_before")
	player.global_position = origin + Vector2(20, 30)
	var boss: SkyCleaver
	while boss == null:
		await get_tree().physics_frame
		if not get_tree().get_nodes_in_group("bosses").is_empty():
			boss = get_tree().get_nodes_in_group("bosses")[0] as SkyCleaver
	var flight: Array[float] = FLIGHT_SHOTS.duplicate()
	var card: Array[float] = CARD_SHOTS.duplicate()
	var index: int = 0
	var frames: int = 0
	while frames < 60 * 16:
		await get_tree().process_frame
		frames += 1
		var intro: BossIntro = boss._intro
		if intro == null:
			if _landed >= 0.0:
				break
			continue
		_landed = intro._land
		if intro._land < 0.0 and not flight.is_empty() and intro._t >= flight[0]:
			print("flight shot ", flight[0], " intro_t ", snappedf(intro._t, 0.01), " boss state ", boss.state, " state_t ", snappedf(boss._state_time, 0.01), " pos ", boss.global_position.round(), " h ", snappedf(boss._height, 1.0))
			await _shot("1_flight_%02d_%.2f" % [index, flight[0]])
			flight.remove_at(0)
			index += 1
		elif intro._land >= 0.0 and not card.is_empty() and intro._land >= card[0]:
			await _shot("2_card_%02d_%.2f" % [index, card[0]])
			card.remove_at(0)
			index += 1
	await get_tree().create_timer(1.0).timeout
	await _shot("3_after")
	var bar: BossBar = get_tree().get_first_node_in_group("boss_bar") as BossBar
	var hud: CanvasLayer = player.get("_hud") as CanvasLayer
	var ok: bool = boss._intro == null and not player.story_lock and not InputManager.ui_blocking and hud.visible and bar.visible
	ok = ok and player.view_shift.length() < 1.0 and absf(player.view_camera().zoom.x - 1.0) < 0.01
	print("BOSS INTRO RESTORE: ", "ok" if ok else "FAILED", " lock ", player.story_lock, " blocking ", InputManager.ui_blocking, " hud ", hud.visible, " bar ", bar.visible, " shift ", player.view_shift, " zoom ", player.view_camera().zoom)
	get_tree().quit(0)
