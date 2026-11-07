extends Node
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass
var checks: int = 0
var failures: int = 0
func _ready() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _run() -> void:
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	world.set_process(false)
	world.get_node("Wildlife").process_mode = Node.PROCESS_MODE_DISABLED
	for c: Vector2i in world._chunks.keys(): world._unload_chunk(c)
	var data: Dictionary = DataRegistry.table("rivers_baked")
	var prop_count: int = 0
	for key: String in data["chunks"]:
		var c: Vector2i = Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
		var build: WorldLevel.ChunkBuild = world._begin_chunk(c)
		world._advance_chunk(build)
		check(not world._chunks.has(c) and world._rivers._materials.is_empty(), "Partial river entered live world")
		world._commit_chunk(build)
		world._finish_commit()
		check(world._chunks[c].node.has_node("RiverSurface"), "Missing streamed river")
		for thing: WorldProp in world._chunks[c].things:
			var plant: Dictionary = DataRegistry.get_entry("plants", thing.kind)
			var radius: float = world._generator._foot(plant, thing.kind, thing.variant) * absf(thing.scale.y)
			check(world._rivers.clear_for_prop(thing.position, radius), "Tree/bush/rock footprint overlaps water")
			prop_count += 1
		world._unload_chunk(c)
		check(world._rivers._materials.is_empty(), "River material leaked after unload")
		await get_tree().process_frame
	# A deliberately moved/scaled authored tree must not bypass the exclusion.
	var edge: Dictionary = data["edges"][int((data["edges"] as Array).size() / 2)]
	var pos: Vector2 = Vector2(float(edge["a"][0]), float(edge["a"][1]))
	var c: Vector2i = Vector2i((pos / 512.0).floor())
	var tile: Vector2i = Vector2i((pos / 16.0).floor())
	var key: String = WorldEdits.key(tile)
	world.edits.props[key] = {"kind": "tree", "variant": 3, "pos": [pos.x, pos.y], "scale": 2.0}
	world._load_chunk(c)
	check(not world._things.has(tile), "Moved editor tree materialized in river")
	check(not world.navigation_floor(pos), "Deep water accepted as enemy navigation floor")
	check(world._rivers.surface_at(pos) == "deep_water", "Deep query does not match water surface")
	var first: Texture2D = world._chunks[c].node.get_node("RiverSurface").texture
	world._unload_chunk(c)
	world._load_chunk(c)
	check(world._chunks[c].node.get_node("RiverSurface").texture == first, "Reload changes river texture")
	world._unload_chunk(c)
	world.edits.props.erase(key)
	# Check real physics: dry-to-deep approach blocks; ford traversal stays open.
	var ford: Array = data["fords"][0]
	var ford_at: Vector2 = Vector2(float(ford[0]), float(ford[1]))
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var cell: Vector2i = Vector2i((ford_at / 512.0).floor()) + Vector2i(dx, dy)
			if not world._chunks.has(cell): world._load_chunk(cell)
	await get_tree().physics_frame
	check(not world._rivers.is_deep(ford_at), "Ford center is blocked as deep water")
	check(world._rivers.surface_at(ford_at) == "shallow_water", "Ford lacks shallow surface")
	var actor: CharacterBody2D = CharacterBody2D.new()
	actor.collision_layer = 0
	actor.collision_mask = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(8, 6)
	shape.shape = box
	actor.add_child(shape)
	world.add_child(actor)
	actor.position = ford_at
	await get_tree().physics_frame
	check(not actor.test_move(actor.global_transform, Vector2(1, 0)), "Ford intersects collision")
	var field_path: String = String((data["chunks"]["%d,%d" % [int(ford_at.x / 512), int(ford_at.y / 512)]] as Dictionary)["field"])
	var field_image: Image = (load(field_path) as Texture2D).get_image()
	var local: Vector2i = Vector2i(ford_at) % 512
	var flow_pixel: Color = field_image.get_pixel(local.x, local.y)
	var across: Vector2 = Vector2(-(flow_pixel.a * 2.0 - 1.0), flow_pixel.b * 2.0 - 1.0).normalized()
	actor.position = ford_at - across * 24.0
	check(not actor.test_move(actor.global_transform, across * 48.0), "Ford traversal across the deep channel is obstructed")
	if not world._chunks.has(c): world._load_chunk(c)
	await get_tree().physics_frame
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = 1
	var deep_collision: bool = false
	for hit: Dictionary in world.get_world_2d().direct_space_state.intersect_shape(query):
		if (hit["collider"] as Node).name == "RiverDepth": deep_collision = true
	check(deep_collision, "Deep query does not have matching physical collision")
	actor.queue_free()
	for cell: Vector2i in world._chunks.keys(): world._unload_chunk(cell)
	for audio: Node in world.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio as AudioStreamPlayer2D).stop()
		(audio as AudioStreamPlayer2D).stream = null
	for audio: Node in world.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
		(audio as AudioStreamPlayer).stream = null
	world.queue_free()
	await get_tree().process_frame
	check(Terrain.patches.filter(func(patch: Node) -> bool: return patch is WorldRivers).is_empty(), "River terrain registry leaked on level exit")
	print("World rivers: %d checks, %d failures; %d land props checked" % [checks, failures, prop_count])
	get_tree().quit(0 if failures == 0 else 1)
