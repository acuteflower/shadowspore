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
		if world != null and world.has_method("loading_step") and world is WorldLevel:
			var build: WorldLevel.ChunkBuild = world.get("_building")
			print("chunks=%d pending=%s paused=%s build=%s jobs=%s" % [(world.get("_chunks") as Dictionary).size(), world.get("_pending_commit") != null, (world.get("_paused_builds") as Dictionary).keys(), str([build.cell, build.phase, build.gen_ready]) if build != null else "none", Jobs.stats])
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
	if world is WorldLevel:
		assert(bool(world.get("_stream_settled")))
		var wildlife: Node = world.get("_wildlife") as Node
		assert(wildlife != null and (wildlife.get("_pending") as Array).is_empty(), "wildlife pending queue must be warm")
		var town: Node = world.get("_town_node") as Node
		assert(town != null and town.get("_build") != null, "town build mode must be warm")
		var player: Node = world.get_node("Players").get_child(0)
		var hud: Node = player.get("_hud") as Node
		assert(hud != null, "player HUD must exist")
		var map_win: Node = hud.get_node_or_null("MapWindow")
		assert(map_win != null and bool(map_win.get("_loaded")), "map window must be warm")
	assert(ticks > 10, "Loading must yield to animation frames")
	print("PASS real loading startup: %s animation frames (max_load=%.1fms, max_post=%.1fms), terrain ready, gameplay resumed" % [ticks, _max_load_ms, _max_post_ms])
	get_tree().quit()
