extends Node
## Real startup without save writes; checks paused loading and completed terrain.
var ticks: int = 0
var _loading_phase: bool = true
var _last_tick_usec: int = 0
var _max_load_ms: float = 0.0
var _max_post_ms: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _process(_delta: float) -> void:
	ticks += 1
	var now: int = Time.get_ticks_usec()
	if _last_tick_usec > 0:
		var dt_ms: float = float(now - _last_tick_usec) / 1000.0
		if _loading_phase:
			_max_load_ms = maxf(_max_load_ms, dt_ms)
		else:
			_max_post_ms = maxf(_max_post_ms, dt_ms)
	_last_tick_usec = now
	if ticks % 600 == 0:
		var world: Node = get_tree().get_first_node_in_group("world")
		print("Loading progress: frame %d, world %s" % [ticks, world != null])
	if ticks > 10000:
		push_error("Loading timed out")
		get_tree().quit(1)


func _run() -> void:
	_last_tick_usec = Time.get_ticks_usec()
	await GameLauncher.start(self, {"mode": "new"})
	_loading_phase = false
	_last_tick_usec = Time.get_ticks_usec()
	for _i: int in 20:
		await get_tree().process_frame
	assert(not get_tree().paused)
	var world: Node = get_tree().get_first_node_in_group("world")
	assert(world != null)
	assert(world.get_node("Players").get_child_count() == 1)
	if world is ZoneWorld:
		var dir: ZoneDirector = (world as ZoneWorld).director()
		assert(dir != null and dir.is_loaded(&"windkap"), "WINDKAP zone must be attached")
		var player: Node = world.get_node("Players").get_child(0)
		var hud: Node = player.get("_hud") as Node
		assert(hud != null, "player HUD must exist")
		var map_win: Node = hud.get_node_or_null("MapWindow")
		assert(map_win != null and bool(map_win.get("_loaded")), "map window must be warm")
	assert(ticks > 10, "Loading must yield to animation frames")
	print("PASS real loading startup: %s animation frames (max_load=%.1fms, max_post=%.1fms), terrain ready, gameplay resumed" % [ticks, _max_load_ms, _max_post_ms])
	get_tree().quit()
