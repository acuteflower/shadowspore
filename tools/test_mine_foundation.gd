extends Node
## Step 1 of the mine (docs/mine.md): the mine's slots do not collide with the interiors, the classification and the level sizes are right,
## large coordinates keep sub-pixel precision for collision, and the world level knows the mine.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("MINE FOUNDATION FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# classification: interiors stay interiors, the mine is its own
	_check(Interiors.slot_at(Vector2(Interiors.POCKET_X0 + 100.0, Interiors.POCKET_Y0 + 100.0)) == 0, "interior slot 0")
	_check(Interiors.slot_at(Vector2(Interiors.POCKET_X0 + 1700.0, Interiors.POCKET_Y0 + 100.0)) == 1, "interior slot 1")
	_check(Interiors.slot_at(Vector2(100.0, 100.0)) == -1, "world is no interior")
	_check(MineManager.level_at(Vector2(100.0, 100.0)) == -1, "world is no mine")
	_check(MineManager.level_at(Vector2(Interiors.POCKET_X0 + 100.0, Interiors.POCKET_Y0 + 100.0)) == -1, "interior is no mine")
	for level: int in [1, 2, 10, 20, 32]:
		var inside: Vector2 = MineManager.origin(level) + Vector2(1234.0, 2345.0)
		_check(MineManager.level_at(inside) == level, "mine level %d found" % level)
		_check(Interiors.slot_at(inside) == -1, "mine level %d is no interior" % level)
		_check(MineManager.level_at(MineManager.origin(level) + Vector2(-300.0, -300.0)) == level, "margin of level %d" % level)
	_check(MineManager.level_at(MineManager.origin(33) + Vector2(10.0, 10.0)) == -1, "beyond the last slot")
	# sizes: 88 .. 304 tiles, multiples of 8, monotone, and inside the slot
	var last: int = 0
	for level: int in range(1, 21):
		var edge: int = MineManager.edge_tiles(level)
		_check(edge % 8 == 0 and edge >= last, "edge of level %d is %d" % [level, edge])
		_check(MineManager.edge_px(level) + MineManager.MARGIN < MineManager.SLOT, "level %d fits its slot" % level)
		last = edge
	_check(MineManager.edge_tiles(1) == 88 and MineManager.edge_tiles(20) == 304, "first and last edge")
	_check(MineManager.edge_tiles(25) == 304, "levels beyond the plan keep the size")
	_check(MineManager.zone(1).id == "stollen" and MineManager.zone(5).id == "stollen" and MineManager.zone(6).id == "stein", "zones 1 and 2")
	_check(MineManager.zone(15).id == "kristall" and MineManager.zone(16).id == "zerfressen" and MineManager.zone(30).id == "zerfressen", "zones 3 and 4")
	# precision: a body at the far end of the deepest slot moves and collides like one at the origin (within a hundredth of a pixel)
	var far: Array[float] = await _drop_test(MineManager.origin(20) + Vector2(3000.0, 3000.0))
	var near: Array[float] = await _drop_test(Vector2(300.0, 300.0))
	_check(absf(far[0] - 2.0) < 0.02, "quarter pixel steps at the end of the mine (%f)" % far[0])
	_check(absf(far[1] - near[1]) < 0.05, "collision at the far end rests like near the origin (%f vs %f)" % [far[1], near[1]])
	# the world level knows the mine
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var mines: MineManager = world.get_node_or_null("Mines") as MineManager
	_check(mines != null and mines.is_in_group("mines"), "world has the Mines node")
	if mines != null:
		var in_level: Vector2 = MineManager.origin(1) + mines.layout(1).tile_center(mines.layout(1).entry) ## a point that is floor in the generated level
		_check(world.navigation_floor(in_level), "mine floor is walkable for enemies")
		_check(not world.navigation_floor(MineManager.origin(1) + Vector2(-200.0, 200.0)) , "outside the level there is no floor")
		mines.entrance = Vector2(1234.0, 567.0)
		_check(Interiors.outer(get_tree(), in_level) == Vector2(1234.0, 567.0), "outer of a mine point is the entrance")
	var outside: Vector2 = Vector2(500.0, 500.0)
	_check(Interiors.outer(get_tree(), outside) == outside, "outer of the world is itself")
	print("MINE FOUNDATION: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


## Moves a small body in quarter pixel steps and then drops it onto a floor; returns [x travelled, rest height above start].
func _drop_test(at: Vector2) -> Array[float]:
	var floor_body: StaticBody2D = StaticBody2D.new()
	var floor_shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(400.0, 16.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = at + Vector2(0.0, 40.0)
	add_child(floor_body)
	var mover: CharacterBody2D = CharacterBody2D.new()
	var mover_shape: CollisionShape2D = CollisionShape2D.new()
	var mover_box: RectangleShape2D = RectangleShape2D.new()
	mover_box.size = Vector2(8.0, 8.0)
	mover_shape.shape = mover_box
	mover.add_child(mover_shape)
	mover.position = at
	add_child(mover)
	await get_tree().physics_frame
	for i: int in 8:
		mover.move_and_collide(Vector2(0.25, 0.0))
	var travelled: float = mover.position.x - at.x
	mover.move_and_collide(Vector2(0.0, 100.0))
	var rest: float = mover.position.y - at.y
	floor_body.queue_free()
	mover.queue_free()
	return [travelled, rest]
