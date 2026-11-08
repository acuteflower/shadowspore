extends Node
func _ready() -> void:
	_run.call_deferred()

func _t(label: String, f: Callable) -> void:
	var t0: int = Time.get_ticks_usec()
	for i: int in 2000:
		f.call(Vector2(780.0 + (i % 50) * 1.7, 640.0 + (i / 50) * 1.3))
	print("%s: %.2f us/call" % [label, (Time.get_ticks_usec() - t0) / 2000.0])

func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var g: PropGenerator = world._generator
	_t("wild", func(p: Vector2) -> float: return g._wild(p))
	_t("shore", func(p: Vector2) -> float: return g._shore(p))
	_t("aspect", func(p: Vector2) -> float: return g.aspect(p))
	_t("damp_at", func(p: Vector2) -> float: return g.damp_at(p))
	_t("water_gap", func(p: Vector2) -> float: return g._water_gap(p))
	_t("level_at", func(p: Vector2) -> float: return world._relief.level_at(p * 16.0))
	# whole-chunk query, cold cache vs warm neighbour
	var c: Vector2i = world._start / WorldLevel.CHUNK + Vector2i(2, 0)
	for k: int in 3:
		var cc: Vector2i = c + Vector2i(k, 0)
		var t0: int = Time.get_ticks_usec()
		var q: PropGenerator.Query = g.begin_chunk(Rect2i(cc * WorldLevel.CHUNK, Vector2i(32, 32)))
		q.advance(0)
		print("HASH %s %d %d" % [cc, hash(str(q.inner)), hash(str(q.outer))])
		print("query chunk %s: %.1f ms, cache %d, inner %d outer %d" % [cc, (Time.get_ticks_usec() - t0) / 1000.0, g._cache.size(), q.inner.size(), q.outer.size()])
	get_tree().quit()
