extends Node
## Real startup without save writes; checks paused loading and completed terrain.
var ticks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _process(_delta: float) -> void:
	ticks += 1
	if ticks % 600 == 0:
		var world: Node = get_tree().get_first_node_in_group("world")
		print("Loading progress: frame %d, world %s" % [ticks, world != null])
		if world != null and world.has_method("loading_step"):
			var build: WorldLevel.ChunkBuild = world.get("_building")
			print("chunks=%d pending=%s paused=%s build=%s jobs=%s" % [(world.get("_chunks") as Dictionary).size(), world.get("_pending_commit") != null, (world.get("_paused_builds") as Dictionary).keys(), str([build.cell, build.phase, build.gen_ready]) if build != null else "none", Jobs.stats])
	if ticks > 10000:
		push_error("Loading timed out")
		get_tree().quit(1)


func _run() -> void:
	await GameLauncher.start(self, {"mode": "new"})
	assert(not get_tree().paused)
	var world: Node = get_tree().get_first_node_in_group("world")
	assert(world != null)
	assert(world.get_node("Players").get_child_count() == 1)
	if world.has_method("loading_step"):
		assert(bool(world.get("_stream_settled")))
	assert(ticks > 10, "Loading must yield to animation frames")
	print("PASS real loading startup: %s animation frames, terrain ready, gameplay resumed" % ticks)
	get_tree().quit()
