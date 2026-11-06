extends Node
## Step 3 of the mine (docs/mine.md): a level is built and streamed around the player, walls block exactly where the layout says, enemies see the floor,
## the camera and tint follow the level, and a level nobody is in is freed.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("MINE LEVEL FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var mines: MineManager = world.get_node("Mines") as MineManager
	var player: Player = world._players.get_child(0) as Player
	var came_from: Vector2 = player.global_position
	mines.enter(player, 1)
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var l: MineLayout = mines.layout(1)
	var built: MineLevel = mines.level_node(1)
	_check(built != null, "level node exists")
	_check(MineManager.level_at(player.global_position) == 1, "player is in level 1")
	_check(player.global_position.distance_to(MineManager.origin(1) + l.tile_center(l.entry)) < 1.0, "player stands in the entry room")
	_check(built.chunks.has(Vector2i(l.entry.x / 32, l.entry.y / 32)), "the entry chunk is built")
	_check(mines.entrance == came_from, "the way back is remembered")
	_check(mines.ambient_color().a > 0.0, "the zone's tint is on")
	_check(Interiors.outer(get_tree(), player.global_position) == came_from, "the world streams round the entrance")
	var camera: Camera2D = player.get("_camera") as Camera2D
	_check(camera.limit_left > 50000 and camera.limit_right < 100000, "camera limited to the level")
	# collision matches the layout in the entry chunk and its neighbours
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var mismatch: int = 0
	var checked: int = 0
	var base: Vector2i = Vector2i(l.entry.x / 32, l.entry.y / 32) * 32
	var props_near: Array[Vector2i] = []
	for entry: Dictionary in l.chunk_props.get(base / 32, []) as Array:
		if MineLevel.SOLID.has(String(entry.kind)):
			props_near.append(Vector2i(floori(float(entry.x) / 16.0), floori(float(entry.y) / 16.0)))
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 3.0
	for ty: int in range(base.y, mini(base.y + 32, l.edge)):
		for tx: int in range(base.x, mini(base.x + 32, l.edge)):
			if props_near.any(func(p: Vector2i) -> bool: return absi(p.x - tx) <= 5 and absi(p.y - ty) <= 5):
				continue ## props bring colliders of their own
			var inner: bool = true
			for n: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
				inner = inner and l.is_floor(tx + n.x, ty + n.y)
			if not inner:
				continue
			var here: Vector2 = MineManager.origin(1) + l.tile_center(Vector2i(tx, ty))
			var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
			query.shape = circle
			query.transform = Transform2D(0.0, here)
			query.collision_mask = 1
			checked += 1
			if not space.intersect_shape(query, 1).is_empty():
				mismatch += 1 ## open floor must be free
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				for k: int in range(1, 14):
					var t: Vector2i = Vector2i(tx, ty) + dir * k
					if not l.is_floor(t.x, t.y):
						var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(here, MineManager.origin(1) + l.tile_center(t), 1)
						checked += 1
						if space.intersect_ray(ray).is_empty():
							mismatch += 1 ## between floor and rock there is an edge
						break
	_check(mismatch == 0, "collision matches the layout (%d of %d wrong)" % [mismatch, checked])
	_check(checked > 200, "enough tiles checked (%d)" % checked)
	_check(mines.navigation_floor(MineManager.origin(1) + l.tile_center(l.entry)), "floor is navigable")
	var wall_tile: Vector2i = Vector2i(2, 2)
	_check(not mines.navigation_floor(MineManager.origin(1) + l.tile_center(wall_tile)), "rock is not navigable")
	# a walker can cross a room and is stopped by the rim
	var walker: CharacterBody2D = CharacterBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(8, 8)
	shape.shape = box
	walker.add_child(shape)
	walker.collision_mask = 1
	walker.position = MineManager.origin(1) + l.tile_center(l.entry)
	add_child(walker)
	await get_tree().physics_frame
	var hit: KinematicCollision2D = walker.move_and_collide(Vector2(-3000, 0))
	var left_edge_tile: float = (walker.position.x - MineManager.origin(1).x) / 16.0
	_check(hit != null and left_edge_tile >= 2.0, "walking west ends at a wall inside the level (%.1f tiles)" % left_edge_tile)
	walker.queue_free()
	# lights: the chunks hold lamp lights, no more than the cap shine
	for i: int in 20:
		await get_tree().process_frame
	var shining: int = 0
	var existing: int = 0
	for built_chunk: MineChunk in built.chunks.values():
		existing += built_chunk.lights.size()
		for light: InteriorLight in built_chunk.lights:
			if light.enabled:
				shining += 1
		_check(built_chunk.decor != null and is_instance_valid(built_chunk.decor), "chunk has its decor")
	_check(existing > 0 and shining <= MineLevel.LIGHT_CAP, "lamp lights exist (%d), at most the cap shine (%d)" % [existing, shining])
	# streaming: jump across a deep level, chunks follow, old ones go
	var l20: MineLayout = mines.layout(20)
	var started: int = Time.get_ticks_usec()
	mines.enter(player, 20)
	var first_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	await get_tree().process_frame
	var deep: MineLevel = mines.level_node(20)
	_check(deep != null and deep.chunks.size() >= 1, "level 20 built (%.0f ms incl. generation)" % first_ms)
	for i: int in 12:
		await get_tree().process_frame
	_check(deep.chunks.size() >= 4 and deep.chunks.size() <= 9, "chunks around the player (%d)" % deep.chunks.size())
	var far_tile: Vector2i = l20.exit
	player.global_position = MineManager.origin(20) + l20.tile_center(far_tile)
	for i: int in 24:
		await get_tree().process_frame
	_check(deep.chunks.has(Vector2i(far_tile.x / 32, far_tile.y / 32)), "the chunk at the exit is built")
	_check(not deep.chunks.has(Vector2i(l20.entry.x / 32, l20.entry.y / 32)) or Vector2i(l20.entry / 32).distance_to(Vector2(far_tile / 32)) <= 2.9, "far chunks are dropped")
	_check(deep.chunks.size() <= 12, "chunk count stays bounded (%d)" % deep.chunks.size())
	var t0: int = Time.get_ticks_usec()
	var probe: MineChunk = MineChunk.new()
	probe.setup(Vector2i(2, 2), l20, load("res://assets/mine/tiles_void.png") as Texture2D)
	var setup_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	probe.free()
	print("chunk setup (collision) %.1f ms" % setup_ms)
	# leaving and unloading
	(MineManager.config().world as Dictionary).unload_seconds = 0.2
	mines.leave(player)
	_check(MineManager.level_at(player.global_position) == -1, "back in the world")
	_check(mines.ambient_color().a == 0.0, "tint is off outside")
	await get_tree().create_timer(0.6).timeout
	_check(mines.level_node(20) == null and mines.level_node(1) == null, "empty levels are freed")
	print("MINE LEVEL: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
