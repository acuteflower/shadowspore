extends Node
## Look study of the caravan (docs/haendler_konzept.md): FERTIGE STADT, a developer visit, captures while it drives on the cart road and once the stall is open.
## `Godot --rendering-driver opengl3 --path . --fixed-fps 60 tools/preview_caravan.tscn -- --dir=/abs/folder [--night]`

var _dir: String = ""


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_run.call_deferred()


func _shot(name_id: String) -> void:
	if _dir == "":
		return
	var path: String = _dir.path_join("caravan_%s.png" % name_id)
	var hero: Player = Player.all[0] if not Player.all.is_empty() else null
	var own: Camera2D = hero.get_node_or_null("Camera2D") as Camera2D if hero != null else null
	if own != null and not own.is_current(): ## something else may have taken the view: the shot is of her
		own.make_current()
		await _frames(30)
	var cam: Camera2D = get_viewport().get_camera_2d()
	print("SHOT ", name_id, " player ", hero.global_position if hero != null else Vector2.ZERO, " camera ", cam.get_screen_center_position() if cam != null else Vector2.ZERO, " cam ", cam.get_path() if cam != null else NodePath())
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURED ", path)


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	await _frames(60)
	world.debug_jump_town()
	await _frames(120)
	player.health.god_mode = true
	TimeManager.set_time(0.40)
	var caravan: CaravanManager = town.caravan
	CaravanRules.set_storm_override(func(_e: float) -> bool: return false)
	caravan.debug_come(1)
	await _frames(2)
	var hud: CanvasLayer = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	var drive: float = float(CaravanRules.cfg().drive_seconds)
	await _frames(int(drive * 60.0 * 0.86))
	player.global_position = caravan.view.global_position + Vector2(-50, 30)
	await _frames(90)
	await _shot("road")
	await _frames(int((drive * 0.14 + float(CaravanRules.cfg().setup_seconds)) * 60.0) + 60)
	player.global_position = caravan.merchant_point() + Vector2(10, 46)
	await _frames(60)
	await _shot("open")
	if "--night" in OS.get_cmdline_user_args():
		TimeManager.set_time(0.9)
		await _frames(60)
		await _shot("night")
	get_tree().quit(0)
