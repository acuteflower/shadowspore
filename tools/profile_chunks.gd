extends Node
## Profiles chunk preparation per phase (headless-capable). Run tools/profile_chunks.tscn.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var start: Vector2i = world._start / WorldLevel.CHUNK
	var tot: Dictionary = {}
	var worst: Dictionary = {}
	var commit_t: Array = []
	var finish_t: Array = []
	var offsets: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]
	for off: Vector2i in offsets:
		var c: Vector2i = start + off
		var build: WorldLevel.ChunkBuild = world._begin_chunk(c)
		var done: bool = false
		while not done:
			var ph: int = build.phase
			var t0: int = Time.get_ticks_usec()
			done = world._advance_chunk(build, t0 + 300)
			var dt: int = Time.get_ticks_usec() - t0
			tot[ph] = int(tot.get(ph, 0)) + dt
			worst[ph] = maxi(int(worst.get(ph, 0)), dt)
		var t1: int = Time.get_ticks_usec()
		world._commit_chunk(build)
		var t2: int = Time.get_ticks_usec()
		world._finish_commit()
		var t3: int = Time.get_ticks_usec()
		commit_t.append((t2 - t1) / 1000.0)
		finish_t.append((t3 - t2) / 1000.0)
		var tt: int = Time.get_ticks_usec()
		print("unload ", c, " ", (Time.get_ticks_usec() - tt) / 1000.0, " ms")
		await get_tree().process_frame
	for ph: int in tot.keys():
		print("PHASE %d: avg %.1f ms/chunk, worst slice %.2f ms" % [ph, tot[ph] / 1000.0 / offsets.size(), worst[ph] / 1000.0])
	print("commit ms ", commit_t)
	print("finish ms ", finish_t)
	get_tree().quit()
