extends Node
## Script-cost profiler of the real world (no save, no game socket). Run windowed:
##   Godot --path . tools/probe_tree.tscn [-- --quality=N --enemies=N --depth=2 --night --top=12]
## Every processing subtree (world children, HUD widgets, autoloads) is switched off (`PROCESS_MODE_DISABLED`)
## and on in turns; the median frame time with and without it is compared several times (drift cancels out),
## then the most expensive subtrees are opened one level deeper. Drawing still happens, so this is the cost of
## `_process` / `_physics_process` (and their queue_redraw -> `_draw` work) of that subtree.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

class ProbeWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_tree().auto_accept_quit = false ## a benchmark window must not be closed halfway
	DisplayServer.window_set_title("SHADOWSPORE BENCHMARK - laeuft, bitte nicht schliessen")
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.trim_prefix("--%s=" % key)
	return fallback


func _run() -> void:
	TimeManager.time_of_day = 0.0 if OS.get_cmdline_user_args().has("--night") else 0.5
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(ProbeWorld)
	add_child(world)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = world._spawn_position(0)
	world.get_node("Players").add_child(player)
	(player.get_node("HealthComponent") as HealthComponent).floor_value = 1.0
	for i: int in 120:
		await get_tree().process_frame
	var enemies: int = int(_arg("enemies", "0"))
	var kinds: Array[String] = ["shadow_spider", "void_listener", "void_crusher"]
	for i: int in enemies:
		world.spawn_species(kinds[i % 3], player.position + Vector2.from_angle(TAU * i / maxf(enemies, 1)) * 140.0, 0.0)
	for i: int in 60:
		await get_tree().process_frame
	var base: float = await _median(150)
	print("BASE median frame %.2f ms (quality %s, enemies %d)" % [base, Quality.NAMES[Quality.effective], enemies])
	var roots: Array[Node] = []
	for child: Node in world.get_children():
		roots.append(child)
	var hud: Node = player.get_node_or_null("Hud")
	if hud == null:
		for c: Node in player.get_children():
			if c is CanvasLayer:
				hud = c
	for child: Node in player.get_children():
		roots.append(child)
	if hud != null:
		roots.erase(hud)
		for c: Node in hud.get_children():
			roots.append(c)
	for auto: Node in get_tree().root.get_children():
		if auto != self and auto != world:
			roots.append(auto)
	var depth: int = int(_arg("depth", "2"))
	var top: int = int(_arg("top", "12"))
	var level: Array[Node] = roots
	for d: int in depth:
		var rows: Array = []
		for node: Node in level:
			if not is_instance_valid(node) or node == player or node.process_mode == Node.PROCESS_MODE_DISABLED or _busy(node) == 0:
				continue
			if OS.get_cmdline_user_args().has("--trace"): print("    .. ", node.get_path())
			var saved: float = await _cost(node)
			rows.append([saved, node])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
		print("--- depth %d" % d)
		var next: Array[Node] = []
		for i: int in mini(rows.size(), top + 6):
			var node: Node = rows[i][1]
			if not is_instance_valid(node):
				continue
			var script: Script = node.get_script() as Script
			print("  %6.2f ms  %-36s %s (%d children)" % [float(rows[i][0]), str(node.get_path()).trim_prefix("/root/ProbeTree/"), script.resource_path.get_file() if script != null else node.get_class(), node.get_child_count()])
			if i < top and float(rows[i][0]) > 0.25:
				for c: Node in node.get_children():
					next.append(c)
		level = next
	get_tree().quit()


## How many nodes of the subtree process (0 = nothing to measure).
func _busy(node: Node) -> int:
	var n: int = 1 if (node.is_processing() or node.is_physics_processing()) else 0
	for c: Node in node.get_children():
		n += _busy(c)
	return n


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("PROBE: window close requested")


## Frame-time saving of switching `node` off: 3 rounds of on/off, medians compared.
func _cost(node: Node) -> float:
	var was: Node.ProcessMode = node.process_mode
	var diffs: Array[float] = []
	for round: int in 3:
		var on: float = await _median(24)
		node.process_mode = Node.PROCESS_MODE_DISABLED
		var off: float = await _median(24)
		node.process_mode = was
		diffs.append(on - off)
	diffs.sort()
	return diffs[1]


func _median(frames: int) -> float:
	for i: int in 4:
		await get_tree().process_frame
	var times: Array[float] = []
	var last: int = Time.get_ticks_usec()
	for i: int in frames:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	return times[frames / 2]
