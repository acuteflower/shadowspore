extends Node
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass
var _failures: int = 0
var _checks: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)

func _make(pop: TinyPopulation, species: String, at: Vector2, tree: FirTree = null) -> TinyWildlife:
	var animal: TinyWildlife = load("res://src/entities/wildlife/tiny_wildlife.tscn").instantiate() as TinyWildlife
	animal.name = "Test_%s" % species
	animal.species = species
	animal.position = at
	animal.home = at
	if tree != null:
		animal.tree_path = String(tree.get_path())
		animal.tree_offset = Vector2(3, -12)
	pop._animals.add_child(animal)
	animal.set_physics_process(false)
	return animal

func _run() -> void:
	TimeManager.time_of_day = 0.5
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	for i: int in 24:
		await get_tree().physics_frame
	var pop: TinyPopulation = world.get_node("Wildlife/SmallResidents") as TinyPopulation
	pop.set_process(false)
	var counts: Dictionary = {"bee":0, "snail":0, "ladybug":0, "moth":0}
	for node: Node in pop._animals.get_children():
		var animal: TinyWildlife = node as TinyWildlife
		counts[animal.species] += 1
		if animal.species == "bee":
			_check(animal.flowers.has(animal.position) or animal.state == TinyWildlife.State.MOVE, "Bee spawned away from actual flowers")
	_check(counts.bee <= 28 and counts.snail <= 22 and counts.ladybug <= 16 and counts.moth == 0, "Small wildlife exceeded sparse caps")
	var bee: TinyWildlife = _make(pop, "bee", world._spawn_position(0))
	bee.flowers = [bee.home, bee.home + Vector2(30, 0), bee.home + Vector2(65, 15)]
	bee._fly(bee.home - Vector2(10, 0))
	_check(bee._to == bee.flowers[2], "Bee did not choose a flower farther from the disturbance")
	bee._elapsed = bee._duration
	bee._physics_process(0)
	_check(bee.state == TinyWildlife.State.FEED and bee.position == bee.flowers[2], "Bee failed to settle on its chosen blossom")
	TimeManager.time_of_day = 0.97
	bee._elapsed = 20
	bee._physics_process(0)
	_check(bee.state == TinyWildlife.State.REST, "Bee did not rest at night")
	TimeManager.time_of_day = 0.5
	var tree: FirTree
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		if node is FirTree and float(((node as FirTree).spec()["clear"] as Array)[(node as FirTree).variant]) >= 24:
			tree = node as FirTree
			break
	_check(tree != null, "World had no real trunk for snail test")
	if tree != null:
		var snail: TinyWildlife = _make(pop, "snail", tree.position, tree)
		_check(snail._visual.get_parent() == tree.get_node("Sprite"), "Tree snail is not attached to the trunk drawing layer")
		snail._act(TinyWildlife.State.MOVE, Vector2(3, -12), Vector2(3, -22), 10, snail.tree_path, snail.tree_offset, 5)
		snail._physics_process(0)
		_check(is_equal_approx(snail.tree_offset.y, -17), "Tree snail did not crawl along the trunk")
		snail._choose(TinyWildlife.State.WITHDRAW, 3)
		_check(snail.state == TinyWildlife.State.WITHDRAW, "Snail did not withdraw into its shell")
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--capture="):
				snail._choose(TinyWildlife.State.REST, 30)
				var den: WildlifeShelter = load("res://src/entities/wildlife/wildlife_shelter.tscn").instantiate() as WildlifeShelter
				den.position = tree.position + Vector2(28, 10)
				world.add_child(den)
				var points: Array[Vector2] = world._flower_targets(Vector2i(floori(tree.position.x / 512), floori(tree.position.y / 512)))
				var closest: Vector2 = tree.position + Vector2(34, 8)
				var distance: float = INF
				for point: Vector2 in points:
					if point.distance_to(tree.position) < distance:
						distance = point.distance_to(tree.position)
						closest = point
				bee._act(TinyWildlife.State.FEED, closest, closest, 30, "", Vector2.ZERO, 0)
				if OS.get_cmdline_user_args().has("--night"):
					TimeManager.time_of_day = 0.97
					var moth: TinyWildlife = _make(pop, "moth", tree.position + Vector2(12, 5))
					moth._act(TinyWildlife.State.MOVE, moth.position, moth.position + Vector2(22, 5), 3, "", Vector2.ZERO, 1.5)
				var lady: TinyWildlife = _make(pop, "ladybug", tree.position + Vector2(20, 8))
				var camera: Camera2D = Camera2D.new()
				camera.position = tree.position + Vector2(20, -10)
				camera.zoom = Vector2(3, 3)
				world.add_child(camera)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var result: Error = get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
				print("Tiny wildlife capture: ", error_string(result))
				get_tree().quit(result)
				return
		tree.state["f"] = 1
		snail._physics_process(0)
		_check(snail.tree_path.is_empty() or snail.is_queued_for_deletion(), "Snail floated on a felled tree")
	# A loaded daytime chunk must populate moths on nightfall, then remove them
	# at dawn and permit a new night without duplicating daytime residents.
	TimeManager.time_of_day = 0.97
	pop._process(0)
	for cell: Vector2i in pop._active:
		pop._populate(cell)
	var moth_count: int = 0
	for node: Node in pop._animals.get_children():
		if (node as TinyWildlife).species == "moth" and not node.is_queued_for_deletion():
			moth_count += 1
	_check(moth_count > 0 and moth_count <= 18, "Nightfall did not populate the existing loaded chunks with moths")
	var moth: TinyWildlife = _make(pop, "moth", bee.home)
	moth.flowers = [moth.home, moth.home + Vector2(35, 0), moth.home + Vector2(60, 20)]
	moth._fly()
	moth._process(0)
	_check(moth.state == TinyWildlife.State.MOVE and moth._visual.visible, "Moth failed to fly visibly at night")
	moth._elapsed = moth._duration
	moth._physics_process(0)
	_check(moth.state == TinyWildlife.State.FEED, "Moth did not perch at its luminous-flora target")
	TimeManager.time_of_day = 0.5
	moth._process(0)
	moth._physics_process(0)
	pop._process(0)
	_check(not moth._visual.visible and moth.is_queued_for_deletion(), "Moth remained visible/alive during the day")
	await get_tree().physics_frame
	var daylight_moths: int = 0
	for node: Node in pop._animals.get_children():
		daylight_moths += int((node as TinyWildlife).species == "moth")
	_check(daylight_moths == 0, "Population retained nocturnal moths after dawn")
	var lady: TinyWildlife = _make(pop, "ladybug", bee.home)
	lady.flowers = [lady.home, lady.home + Vector2(24, 0)]
	lady._fly()
	_check(lady.state == TinyWildlife.State.FLY, "Ladybug did not switch from crawling to a short relocation flight")
	lady._elapsed = lady._duration
	lady._physics_process(0)
	_check(lady.state == TinyWildlife.State.FEED, "Ladybug did not settle after landing")
	var den: Image = (load("res://assets/wildlife/badger_den.png") as Texture2D).get_image()
	_check(den.get_size() == Vector2i(40, 24), "Den changed its established footprint")
	print("Tiny wildlife: %d checks, %d failures; natural bee/snail counts %s" % [_checks, _failures, counts])
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
