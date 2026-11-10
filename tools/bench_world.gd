extends Node
## Frame-time benchmark of the real world (no save, no game socket). Run windowed so drawing counts:
##   Godot --rendering-driver opengl3 --path . tools/bench_world.tscn [-- --enemies=N --run=px_per_s --dir=x,y]
## Phases: idle at the start, a straight sprint (counts frames where the camera sees an unloaded chunk), enemies round the player.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

class BenchWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass

var _times: PackedFloat32Array = PackedFloat32Array()
var _proc: float = 0.0
var _phys: float = 0.0
var _holes: int = 0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.trim_prefix("--%s=" % key)
	return fallback


func _run() -> void:
	var enemies: int = int(_arg("enemies", "10"))
	var speed: float = float(_arg("run", "180"))
	var dir_parts: PackedStringArray = _arg("dir", "1,0.35").split(",")
	var dir: Vector2 = Vector2(float(dir_parts[0]), float(dir_parts[1])).normalized()
	TimeManager.time_of_day = 0.5
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(BenchWorld)
	add_child(world)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = world._spawn_position(0)
	world.get_node("Players").add_child(player)
	player.set_physics_process(false)
	var health: HealthComponent = player.get_node("HealthComponent") as HealthComponent
	health.floor_value = 1.0
	for i: int in 60:
		await get_tree().process_frame
	var quick: bool = OS.get_cmdline_user_args().has("--quick")
	await _measure("idle", 300, func(_d: float) -> void: pass)
	if OS.get_cmdline_user_args().has("--probe") and not quick:
		await _probe()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	await _measure("sprint", 60 if quick else 900, func(d: float) -> void:
		player.position += dir * speed * d
		_count_hole(world, camera))
	print("  frames with a visible unloaded chunk: %d" % _holes)
	var origin: Vector2 = player.position
	for i: int in 30:
		await get_tree().process_frame
	var kinds: Array[String] = ["shadow_spider", "void_listener", "void_crusher"]
	if _arg("kind", "") != "":
		kinds = [_arg("kind", "")]
	var spawned: int = 0
	var actors: Array[Node2D] = []
	for i: int in enemies:
		var at: Vector2 = origin + Vector2.from_angle(TAU * i / maxf(enemies, 1)) * 140.0
		var actor: Node2D = world.spawn_species(kinds[i % kinds.size()], at, 0.0)
		if actor != null:
			spawned += 1
			actors.append(actor)
	print("  spawned %d enemies" % spawned)
	for i: int in 60:
		await get_tree().process_frame
	await _measure("enemies", 600, func(_d: float) -> void:
		player.position = origin)
	if OS.get_cmdline_user_args().has("--split"):
		var base: float = await _avg(240)
		for a: Node2D in actors: if is_instance_valid(a): a.visible = false
		var hidden: float = await _avg(240)
		for a: Node2D in actors: if is_instance_valid(a): a.visible = true
		for a: Node2D in actors: if is_instance_valid(a): a.set_physics_process(false)
		var nophys: float = await _avg(240)
		for a: Node2D in actors: if is_instance_valid(a): a.set_physics_process(true)
		for a: Node2D in actors: if is_instance_valid(a): a.set_process(false)
		var noproc: float = await _avg(240)
		for a: Node2D in actors: if is_instance_valid(a): a.set_process(true)
		var clocks: Array = []
		for a: Node2D in actors:
			if not is_instance_valid(a): continue
			for child: Node in a.find_children("*", "", true, false):
				var clock: Variant = child.get("_clock")
				if clock is RigClock: clocks.append(clock)
		for clock: RigClock in clocks:
			clock.hz = 0.001
			clock.fast_hz = 0.001
		var frozen: float = await _avg(240)
		for clock: RigClock in clocks:
			clock.hz = 30.0
			clock.fast_hz = 60.0
		print("  split: rig frozen (no GDScript draw, still rendered) %.2f -> GDScript redraw+update %.2f, rendering %.2f" % [frozen, base - frozen, frozen - hidden])
		print("  split: frame %.2f | drawing %.2f | physics/AI %.2f | _process (rig update + redraw) %.2f ms" % [base, base - hidden, base - nophys, base - noproc])
	if OS.get_cmdline_user_args().has("--probe"):
		await _probe()
	get_tree().quit()


## Switches off _process/_physics_process of every node of one script (or node class) at a time and prints how much the frame got faster.
func _probe() -> void:
	var groups: Dictionary = {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if node == self or node == get_tree().root:
			continue
		var key: String = node.get_class()
		var script: Script = node.get_script() as Script
		if script != null:
			key = script.resource_path.get_file()
		if node.is_processing() or node.is_physics_processing():
			(groups.get_or_add(key, []) as Array).append(node)
	var base: float = await _avg(120)
	var rows: Array = []
	for key: String in groups:
		var nodes: Array = groups[key]
		var was: Array = []
		for item: Variant in nodes:
			if not is_instance_valid(item):
				was.append([false, false])
				continue
			var node: Node = item as Node
			was.append([node.is_processing(), node.is_physics_processing()])
			node.set_process(false)
			node.set_physics_process(false)
		var t: float = await _avg(90)
		for i: int in nodes.size():
			if is_instance_valid(nodes[i]):
				(nodes[i] as Node).set_process(bool(was[i][0]))
				(nodes[i] as Node).set_physics_process(bool(was[i][1]))
		rows.append([base - t, key, nodes.size()])
		base = await _avg(60)
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for row: Array in rows.slice(0, 25):
		print("  probe %-40s x%-5d saves %.2f ms" % [row[1], row[2], row[0]])


func _avg(frames: int) -> float:
	for i: int in 10:
		await get_tree().process_frame
	var t0: int = Time.get_ticks_usec()
	for i: int in frames:
		await get_tree().process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / frames


func _count_hole(world: WorldLevel, camera: Camera2D) -> void:
	var view: Vector2 = Vector2(640, 360) / camera.zoom
	var center: Vector2 = camera.get_screen_center_position()
	var lo: Vector2i = Vector2i(((center - view * 0.5) / (16.0 * WorldLevel.CHUNK)).floor())
	var hi: Vector2i = Vector2i(((center + view * 0.5) / (16.0 * WorldLevel.CHUNK)).floor())
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			if not world._chunks.has(Vector2i(x, y)):
				_holes += 1
				return


func _measure(label: String, frames: int, step: Callable) -> void:
	_times.clear()
	_proc = 0.0
	_phys = 0.0
	var last: int = Time.get_ticks_usec()
	for i: int in frames:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var dt: float = (now - last) / 1000.0
		last = now
		_times.append(dt)
		_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		step.call(dt / 1000.0)
	var sorted: PackedFloat32Array = _times.duplicate()
	sorted.sort()
	var total: float = 0.0
	for t: float in _times: total += t
	var over: int = 0
	for t: float in _times:
		if t > 16.7: over += 1
	print("%-8s avg %.2f ms  p50 %.2f  p95 %.2f  p99 %.2f  max %.2f  >16.7ms: %d | process %.2f  physics %.2f  nodes %d  draw calls %d" % [label, total / frames,
		sorted[frames / 2], sorted[int(frames * 0.95)], sorted[int(frames * 0.99)], sorted[frames - 1], over, _proc / frames, _phys / frames,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
