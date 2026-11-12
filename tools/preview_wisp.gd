extends Node2D
## Look study of the wisp trail (docs/raetsel_konzept.md 1): a short route on plain grass, a stand-in follower (teal ring), captures of sleep,
## wake, flight, call, fright, dive and bloom with the chest. Offline, no world, no save.
##   Godot --rendering-driver opengl3 --path . tools/preview_wisp.tscn -- --dir=/abs/folder [--night]

var _dir: String = ""
var _night: bool = false
var _trail: WispTrail
var _follower: Dictionary = {"pos": Vector2(0, 260), "sneak": false, "loud": false}
var _cam: Camera2D
var _dot: Node2D


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.substr(6)
		elif arg == "--night":
			_night = true
	var ground: ColorRect = ColorRect.new()
	ground.color = Color("3a5a3c") if not _night else Color("1b2a26")
	ground.size = Vector2(4000, 3000)
	ground.position = Vector2(-2000, -1500)
	ground.z_index = -20
	add_child(ground)
	if _night:
		var dark: CanvasModulate = CanvasModulate.new()
		dark.color = Color(0.3, 0.3, 0.46)
		add_child(dark)
	var chests: LootChests = LootChests.new()
	add_child(chests)
	_trail = WispTrail.new()
	var route: Array = [[0, 0], [2, -6], [7, -10], [13, -10], [18, -6], [20, 0], [18, 6]]
	_trail.setup({"id": "preview", "tier": "common", "route": route, "stops": [2, 4, 6], "linger": []}, DataRegistry.table("puzzles").get("wisp", {}) as Dictionary)
	_trail.position = -Vector2(8, 8)
	_trail.followers = func() -> Array: return [_follower.duplicate()]
	_trail.solved.connect(func(_id: String, at: Vector2) -> void: chests.appear("preview", "common", at - Vector2(8, 8), true))
	add_child(_trail)
	_trail.set_night(1.0 if _night else 0.0)
	_dot = Node2D.new()
	_dot.z_index = 3
	_dot.draw.connect(func() -> void: _dot.draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 16, Color("78f4e6"), 1.0))
	add_child(_dot)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(2, 2)
	add_child(_cam)
	_run.call_deferred()


func _process(delta: float) -> void:
	_dot.position = (_follower.pos as Vector2) - Vector2(8, 8)
	var focus: Vector2 = _trail.ground_position() - Vector2(8, 8) + Vector2(0, -14)
	_cam.position = _cam.position.lerp(focus, 1.0 - exp(-4.0 * delta))


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	if _dir != "":
		get_viewport().get_texture().get_image().save_png(_dir.path_join("wisp_%s%s.png" % [name, "_night" if _night else ""]))


func _follow(keep: float, seconds: float, until: Callable = Callable()) -> void:
	var t: float = 0.0
	while t < seconds:
		var dt: float = get_process_delta_time()
		t += dt
		var goal: Vector2 = _trail.ground_position()
		var pos: Vector2 = _follower.pos as Vector2
		var d: float = pos.distance_to(goal)
		if d > keep:
			_follower.pos = pos.move_toward(goal, minf(62.0 * dt, d - keep))
		if until.is_valid() and bool(until.call()):
			return
		await get_tree().process_frame


func _run() -> void:
	_cam.position = _trail.bowl_position() - Vector2(8, 22)
	await get_tree().create_timer(0.8).timeout
	await _snap("1_sleep")
	_follower.pos = _trail.bowl_position() + Vector2(10, 45)
	await get_tree().create_timer(0.5).timeout
	await _snap("2_wake")
	await _follow(60.0, 2.6)
	await _snap("3_fly")
	await _follow(60.0, 8.0, func() -> bool: return _trail.state == WispTrail.State.HOVER)
	_follower.pos = _trail.ground_position() + Vector2(-40, 170)
	await get_tree().create_timer(1.3).timeout
	await _snap("4_call")
	_follower.loud = true
	_follower.pos = _trail.ground_position() + Vector2(-20, 40)
	await get_tree().create_timer(0.25).timeout
	await _snap("5_scare")
	_follower.loud = false
	_follower.sneak = true
	await _follow(40.0, 30.0, func() -> bool: return _trail.state == WispTrail.State.DIVE)
	await get_tree().create_timer(0.7).timeout
	await _snap("6_dive")
	await get_tree().create_timer(0.85).timeout
	await _snap("7_impact")
	await get_tree().create_timer(1.0).timeout
	await _snap("8_light")
	await get_tree().create_timer(2.5).timeout
	await _snap("9_bloom")
	print("PREVIEW WISP DONE")
	get_tree().quit()
