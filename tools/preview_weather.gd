extends Node
## Weather captures of the real world. `-- --dir=/abs/folder [--states=fair,rain,storm] [--time=0.5] [--at=x,y tile] [--settle=150] [--flash]`
## Forces each named state (WeatherManager.force), lets the eye settle, saves one png per state. Offline, no save access.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var dir: String = ""
	var states: PackedStringArray = "clear,broken,overcast,rain,storm".split(",")
	var time: float = 0.5
	var tile: Vector2 = Vector2.ZERO
	var settle: int = 150
	var flash: bool = false
	var soaked: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=")
		if arg.begins_with("--states="): states = arg.trim_prefix("--states=").split(",")
		if arg.begins_with("--time="): time = float(arg.trim_prefix("--time="))
		if arg.begins_with("--settle="): settle = int(arg.trim_prefix("--settle="))
		if arg == "--flash": flash = true
		if arg == "--soaked": soaked = true
		if arg.begins_with("--at="):
			var parts: PackedStringArray = arg.trim_prefix("--at=").split(",")
			tile = Vector2(float(parts[0]), float(parts[1]))
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	world.set_process(false)
	world.opening_over = true
	var at: Vector2 = world._spawn_position(0) if tile == Vector2.ZERO else tile * 16.0
	var cell: Vector2i = Vector2i((at / 512.0).floor())
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var c: Vector2i = cell + Vector2i(dx, dy)
			if not world._chunks.has(c): world._load_chunk(c)
	var camera: Camera2D = Camera2D.new()
	camera.position = at
	world.add_child(camera)
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.day = 5
	TimeManager.time_of_day = time
	for s: String in states:
		var w: WeatherManager = WeatherManager.current
		w.force(s, 0.0)
		if soaked:
			w._extra_wet = 1.0
			w.ground_wet = 1.0
		for i: int in settle:
			await get_tree().process_frame
		if flash:
			w.flash_info = {"x": 0.55, "y": 0.78, "far": 0.1, "seed": 4242, "bolt": true, "double": false, "color": Color(0.8, 0.84, 1.0), "peak": 1.0}
			w.flash_age = 0.0
			await get_tree().process_frame
			await get_tree().process_frame
		print("state ", s, " -> ", w.state_id, " cloud ", snappedf(w.cloud, 0.01), " rain ", snappedf(w.rain, 0.01), " local ", snappedf(w.local_rain, 0.01), " wet ", snappedf(w.ground_wet, 0.01), " flash ", snappedf(w.flash, 0.01))
		if dir.is_empty(): continue
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, s])
	print("weather capture done at ", at)
	get_tree().quit()
