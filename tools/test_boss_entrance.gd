extends Node
## Headless check of the boss entrance: no boss before somebody steps into the arena, then it spawns off-screen, flies in, lands on its pillar and the bar appears.
func _ready() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	print("BOSS ENTRANCE: FAILED - ", message)
	get_tree().quit(1)


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var spec: Dictionary = (DataRegistry.table("ground").get("arenas", []) as Array)[0] as Dictionary
	var tile: Array = spec.tile as Array
	var origin: Vector2 = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
	for i: int in 30:
		await get_tree().physics_frame
	if not get_tree().get_nodes_in_group("bosses").is_empty():
		return _fail("a boss exists before anybody entered the arena")
	var bar: BossBar = get_tree().get_first_node_in_group("boss_bar") as BossBar
	# just outside the floor: still nothing
	player.global_position = origin + Vector2(400, 400)
	for i: int in 40:
		await get_tree().physics_frame
	if not get_tree().get_nodes_in_group("bosses").is_empty():
		return _fail("a boss appeared outside the arena")
	# onto the floor: stepping in alone no longer wakes him, only the story does (knight / hologram -> request_arena_boss)
	var inside: Vector2 = origin + Vector2(20, -40)
	player.global_position = inside
	for i: int in 60:
		await get_tree().physics_frame
	if not get_tree().get_nodes_in_group("bosses").is_empty():
		return _fail("a boss appeared just because somebody stood on the floor")
	world.request_arena_boss(String(spec.id), inside)
	var boss: SkyCleaver
	for i: int in 60:
		await get_tree().physics_frame
		if not get_tree().get_nodes_in_group("bosses").is_empty():
			boss = get_tree().get_nodes_in_group("bosses")[0] as SkyCleaver
			break
	if boss == null:
		return _fail("no boss after stepping into the arena")
	if boss.state != SkyCleaver.State.FLYING:
		return _fail("boss does not fly in (state %d)" % boss.state)
	print("entered at ", boss.global_position, " height ", boss._height, " player ", player.global_position)
	if boss.global_position.distance_to(player.global_position) < 430.0:
		return _fail("the boss appears on the screen")
	if bar.visible:
		return _fail("the bar is already there during the flight")
	var landed: bool = false
	for i: int in 60 * 8:
		await get_tree().physics_frame
		if boss.state == SkyCleaver.State.PERCHED:
			landed = true
			break
	if not landed:
		return _fail("never landed (state %d)" % boss.state)
	var pillar_foot: Vector2 = boss._perch_pos(boss.pillar_index)
	if boss.global_position.distance_to(pillar_foot) > 1.0 or absf(boss._height - boss._perch_height(boss.pillar_index)) > 1.0:
		return _fail("not on the pillar: %s h %f" % [boss.global_position, boss._height])
	await get_tree().process_frame
	await get_tree().process_frame
	if not bar.visible:
		return _fail("no boss bar after landing")
	print("BOSS ENTRANCE: ok")
	get_tree().quit(0)
