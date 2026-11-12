extends Node
## Regression for atomic chunk activation, cancellation, editor invalidation and HUD caches.
## Run tools/test_streaming_performance.tscn; no save or authored map is written.
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func signature(world: WorldLevel, c: Vector2i) -> Array:
	var chunk: WorldLevel.Chunk = world._chunks[c]
	var result: Array = []
	for biome: String in chunk.cells:
		for cell: Vector2i in chunk.cells[biome]:
			result.append([biome, cell, (world._layers[biome] as TileMapLayer).get_cell_atlas_coords(cell)])
	result.append(chunk.glow_cells.duplicate())
	for thing: WorldProp in chunk.things:
		result.append([thing.cell, thing.kind, thing.variant, thing.position, thing.scale, thing.state.duplicate(true)])
	for child: Node in chunk.node.get_children():
		if child is StaticBody2D:
			var shapes: Array = []
			for shape: CollisionShape2D in child.get_children():
				shapes.append([shape.position, (shape.shape as RectangleShape2D).size])
			result.append(shapes)
		elif child is MeadowDetails:
			var plants: Array = []
			for i: int in child.multimesh.instance_count:
				plants.append([child.multimesh.get_instance_transform_2d(i), child.multimesh.get_instance_color(i), child.multimesh.get_instance_custom_data(i)])
			result.append(plants)
	return result

func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	# _ready queues authored guards/props. Let those finish before measuring
	# whether a detached chunk build adds anything to the live world.
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2i = world._start / WorldLevel.CHUNK + Vector2i(2, 0)
	var before_props: int = world._things.size()
	var before_cells: int = world._ground.get_used_cells().size()
	var before_interactions: int = get_tree().get_nodes_in_group("interactables").size()
	var build: WorldLevel.ChunkBuild = world._begin_chunk(c)
	var slices: int = 0
	var largest: int = 0
	var total: int = 0
	var complete: bool = false
	while not complete:
		var began: int = Time.get_ticks_usec()
		complete = world._advance_chunk(build, began + WorldLevel.STREAM_BUDGET_USEC)
		var elapsed: int = Time.get_ticks_usec() - began
		total += elapsed
		largest = maxi(largest, elapsed)
		slices += 1
		check(not world._chunks.has(c) and world._things.size() == before_props and world._ground.get_used_cells().size() == before_cells and get_tree().get_nodes_in_group("interactables").size() == before_interactions, "preparation slice %d has no live-world side effects" % slices)
		await get_tree().process_frame
	check(slices > 1, "runtime chunk preparation spans multiple frames")
	var began: int = Time.get_ticks_usec()
	world._commit_chunk(build)
	world._finish_commit()
	print("TIMING cold preparation: %.2f ms total, %.2f ms largest slice, %d slices; commit %.2f ms" % [total / 1000.0, largest / 1000.0, slices, (Time.get_ticks_usec() - began) / 1000.0])
	check(world._chunks.has(c) and world._things.size() >= before_props, "complete chunk activates atomically")
	var staged: Array = signature(world, c)
	world._unload_chunk(c)
	world._load_chunk(c)
	check(signature(world, c) == staged, "staged and synchronous ground, props, plants and collision are identical")

	# Moved/scaled props across chunk borders must obstruct the same decorative plants.
	var authored: Dictionary = world.edits.data()
	var custom: Vector2i = c * WorldLevel.CHUNK + Vector2i(7, 9)
	world.edits.props[WorldEdits.key(custom)] = {"kind": "bush", "variant": 0, "pos": [float(custom.x * 16 + 26), float(custom.y * 16 + 2)], "scale": 1.35, "flip": true}
	world._unload_chunk(c)
	world._load_chunk(c)
	var custom_sync: Array = signature(world, c)
	world._unload_chunk(c)
	build = world._begin_chunk(c)
	while not world._advance_chunk(build, Time.get_ticks_usec() + WorldLevel.STREAM_BUDGET_USEC):
		await get_tree().process_frame
	world._commit_chunk(build)
	world._finish_commit()
	check(signature(world, c) == custom_sync, "authored moved/scaled props survive incremental loading")
	world.edits.assign(authored)

	world._building = world._begin_chunk(c + Vector2i(1, 0))
	while world._building.phase < 4:
		world._advance_chunk(world._building, Time.get_ticks_usec() + 500)
	var abandoned: Node2D = world._building.chunk.node
	var prepared: WorldProp = world._building.chunk.things[0] if not world._building.chunk.things.is_empty() else null
	world._discard_chunk_build()
	check(world._building == null and not is_instance_valid(abandoned) and not is_instance_valid(prepared), "cancelled preparations free detached nodes and props")
	# A teleport overrides an abandoned background job and makes the destination ready now.
	var player: Player = world._players.get_child(0) as Player
	var old_position: Vector2 = player.position
	var destination: Vector2i = c + Vector2i(3, 0)
	world._building = world._begin_chunk(c + Vector2i(1, 0))
	abandoned = world._building.chunk.node
	player.position = Vector2(destination * WorldLevel.CHUNK) * 16.0 + Vector2(256, 256)
	world._stream(false)
	check(world._chunks.has(destination) and world._building == null and not is_instance_valid(abandoned), "teleport completes destination and cancels stale preparation")
	player.position = old_position
	world._building = world._begin_chunk(c + Vector2i(1, 0))
	world.editor_apply(authored, false)
	check(world._building == null, "editor changes invalidate pending preparation")

	var first: Mesh = PixelText._mesh("ÄÖÜ ß: 123")
	check(first == PixelText._mesh("äöü ß: 123"), "equivalent pixel text reuses geometry")
	for i: int in PixelText.CACHE_LIMIT + 10: PixelText._mesh("X %d" % i)
	check(PixelText._meshes.size() <= PixelText.CACHE_LIMIT, "dynamic text cache stays bounded")
	check(PixelText._mesh("") == null and PixelText._mesh("   ").get_surface_count() == 0, "empty and space-only text remains invisible")
	world.free()
	print("STREAMING PERFORMANCE: ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
