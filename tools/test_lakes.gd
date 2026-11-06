extends Node
## Every lake in the real streamed world: enter shallows, blocked depths, reload and cleanup.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass

var _checks: int = 0
var _failures: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("LAKES: " + message)


func _point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	world.set_process(false)
	world.get_node("Wildlife").process_mode = Node.PROCESS_MODE_DISABLED
	world._rivers.fauna.set_process(false)
	for cell: Vector2i in world._chunks.keys(): world._unload_chunk(cell)
	var actor: CharacterBody2D = CharacterBody2D.new()
	actor.collision_layer = 0
	actor.collision_mask = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(8, 6)
	shape.shape = box
	actor.add_child(shape)
	world.add_child(actor)
	for lake: Dictionary in DataRegistry.table("lakes_baked")["lakes"]:
		var id: String = String(lake.id)
		var shore: Vector2 = _point(lake.shore)
		var dry: Vector2 = _point(lake.dry)
		var deep: Vector2 = _point(lake.deep)
		_check(world._rivers.lake_at(shore) and world._rivers.lake_at(deep), id + " is classified as lake")
		_check(world._rivers.surface_at(shore) == "shallow_water", id + " has a shallow shore")
		_check(world._rivers.is_deep(deep), id + " has a deep center")
		_check(Terrain.surface_at(shore) == "shallow_water", id + " uses existing water footsteps")
		_check(float(world._rivers.wade_data(shore, {}).get("submerge", 0)) > 0, id + " uses existing wading")
		for point: Vector2 in [shore, dry, deep]:
			var cell: Vector2i = Vector2i((point / 512.0).floor())
			if not world._chunks.has(cell):
				var build: WorldLevel.ChunkBuild = world._begin_chunk(cell)
				world._advance_chunk(build)
				_check(not world._chunks.has(cell), id + " remains hidden during preparation")
				world._commit_chunk(build)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(world.navigation_floor(shore) and not world.navigation_floor(deep), id + " navigation matches shallow/deep water")
		actor.position = dry
		_check(not actor.test_move(actor.global_transform, shore-dry), id + " old void collider no longer blocks the shore")
		var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
		query.shape = box
		query.transform = Transform2D(0, deep)
		query.collision_mask = 1
		var blocked: bool = false
		for hit: Dictionary in world.get_world_2d().direct_space_state.intersect_shape(query):
			if (hit.collider as Node).name == "RiverDepth": blocked = true
		_check(blocked, id + " deep water has physical collision")
		var cell: Vector2i = Vector2i((shore / 512.0).floor())
		var first: Texture2D = world._chunks[cell].node.get_node("RiverSurface").texture
		world._unload_chunk(cell)
		world._load_chunk(cell)
		_check(world._chunks[cell].node.get_node("RiverSurface").texture == first, id + " reload preserves its surface")
		for loaded: Vector2i in world._chunks.keys(): world._unload_chunk(loaded)
		_check(world._rivers._materials.is_empty(), id + " materials released on unload")
		await get_tree().process_frame
	actor.queue_free()
	world.queue_free()
	await get_tree().process_frame
	_check(Terrain.patches.filter(func(patch: Node) -> bool: return patch is WorldRivers).is_empty(), "water registry cleans up")
	print("LAKES: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
