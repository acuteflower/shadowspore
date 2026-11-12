extends Node
const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")
## Offline real-world wildlife workbench, no save or game-port access.
## Modes:
##   default: woodland showcase (boar sounder, lynx, squirrel, badger + den, deer, fox)
##   --river: river showcase (heron + otter swimming, periscope, back-floating fish feast)
##   --hexenwald: Hexenwald showcase (hex_goat rearing & watching, hex_toad croaking & tongue-lash, phantom Eagle-Owl)

class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _make(population: WoodlandPopulation, species: String, appearance: int, at: Vector2) -> WoodlandMammal:
	var radius: float = float(DataRegistry.get_entry("wildlife", species)["body_radius"]) + 3.0
	var found: bool = false
	for ring: int in 12:
		for sector: int in 12:
			var candidate: Vector2 = at + Vector2.from_angle(float(sector) * TAU / 12.0) * float(ring) * 12.0
			if population.home_loaded(candidate) and bool(population._habitat.call(candidate, species)) and population._clear(candidate, radius):
				at = candidate
				found = true
				break
		if found:
			break
	var animal: WoodlandMammal = load("res://src/entities/wildlife/woodland_mammal.tscn").instantiate() as WoodlandMammal
	animal.name = "Preview_%s_%d_%d" % [species, appearance, population._residents.get_child_count()]
	animal.species = species
	animal.appearance = appearance
	animal.position = at
	animal.home = at
	population._residents.add_child(animal)
	return animal


func _run() -> void:
	var capture: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var river_mode: bool = args.has("--river")
	var hex_mode: bool = args.has("--hexenwald")
	var birds_mode: bool = args.has("--birds")
	var target_tod: float = 0.5 if args.has("--day") else 0.797
	TimeManager.time_of_day = target_tod
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	TimeManager.unlock()
	TimeManager.set_time(target_tod)
	var center: Vector2 = world._spawn_position(0) + Vector2(-80, -620)
	if river_mode:
		var rdata: Dictionary = DataRegistry.table("rivers_baked")
		for key: String in rdata["chunks"]:
			var cell: Vector2i = Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
			for attempt: int in 120:
				var pt: Vector2 = Vector2(cell) * 512.0 + Vector2(96.0 + float((attempt * 37) % 320), 96.0 + float((attempt * 53) % 320))
				var f: Vector2 = world._rivers.field_at(pt)
				if f.x > -7.5 and f.x < -2.5 and f.y < 0.42:
					center = pt
					break
			if center != world._spawn_position(0) + Vector2(-80, -620):
				break
	elif hex_mode:
		center = Vector2(812.0 * 16.0, 882.0 * 16.0)
	elif birds_mode:
		center = world._spawn_position(0) + Vector2(-235, -575)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = center + (Vector2(-155, 82) if (birds_mode or river_mode or hex_mode) else Vector2(-270, 150))
	world.get_node("Players").add_child(player)
	if not capture.is_empty():
		(player.get_node("Camera2D") as Camera2D).enabled = false
		var camera: Camera2D = Camera2D.new()
		camera.position = center + (Vector2(0, 0) if (river_mode or hex_mode or birds_mode) else Vector2(-10, 88))
		world.add_child(camera)
		camera.make_current()
	for frame: int in 24:
		await get_tree().physics_frame
	if river_mode:
		var rpop: RiverFauna = world._rivers.fauna
		rpop.set_process(false)
		for existing: Node in rpop.animals.get_children():
			existing.queue_free()
		await get_tree().process_frame
		var water_pts: Array[Vector2] = []
		var bank_pts: Array[Vector2] = []
		for ring: int in range(1, 14):
			for sec: int in 20:
				var probe: Vector2 = center + Vector2.from_angle(float(sec) * TAU / 20.0) * float(ring) * 8.0
				var fx: float = world._rivers.field_at(probe).x
				if fx < -3.0 and fx > -14.0 and water_pts.size() < 8:
					var ok_w: bool = true
					for prev_w: Vector2 in water_pts:
						if prev_w.distance_to(probe) < 22.0:
							ok_w = false
							break
					if ok_w:
						water_pts.append(probe)
				elif fx > 1.8 and fx < 7.5 and bank_pts.size() < 4:
					var ok_b: bool = true
					for prev_b: Vector2 in bank_pts:
						if prev_b.distance_to(probe) < 22.0:
							ok_b = false
							break
					if ok_b:
						bank_pts.append(probe)
		while water_pts.size() < 6:
			water_pts.append(center + Vector2(float(water_pts.size() * 18 - 40), 0.0))
		while bank_pts.size() < 2:
			bank_pts.append(center + Vector2(46.0, float(bank_pts.size() * 20 - 10)))
		var poses: Array[Dictionary] = [
			{"kind": "duck", "pos": water_pts[0], "school": "dpair_0", "member": 0, "mode": RiverAnimal.Mode.TRAVEL, "aux": 0, "facing": PI * 0.14, "elapsed": 0.45},
			{"kind": "duck", "pos": water_pts[1], "school": "dpair_0", "member": 1, "mode": RiverAnimal.Mode.DABBLE, "aux": 0, "facing": PI * 0.22, "elapsed": 1.05},
			{"kind": "duck", "pos": water_pts[2], "school": "duckfamily_0", "member": 0, "mode": RiverAnimal.Mode.TRAVEL, "aux": 0, "facing": PI * 0.85, "elapsed": 0.35},
			{"kind": "duck", "pos": water_pts[2] + Vector2(11, 3), "school": "duckfamily_0", "member": 1, "mode": RiverAnimal.Mode.TRAVEL, "aux": 0, "facing": PI * 0.85, "elapsed": 0.35},
			{"kind": "duck", "pos": water_pts[2] + Vector2(20, 6), "school": "duckfamily_0", "member": 2, "mode": RiverAnimal.Mode.TRAVEL, "aux": 0, "facing": PI * 0.85, "elapsed": 0.35},
			{"kind": "duck", "pos": bank_pts[0], "school": "dshore_0", "member": 0, "mode": RiverAnimal.Mode.TRAVEL, "aux": 0, "facing": PI * 0.65, "elapsed": 0.4},
			{"kind": "heron", "pos": bank_pts[1], "school": "h_0", "member": 0, "mode": RiverAnimal.Mode.REST, "aux": 0, "facing": PI * 0.18, "elapsed": 0.2},
			{"kind": "otter", "pos": water_pts[3], "school": "o_0", "member": 0, "mode": RiverAnimal.Mode.STRIKE, "aux": 1, "facing": PI * 0.15, "elapsed": 1.6},
			{"kind": "otter", "pos": water_pts[4], "school": "o_1", "member": 0, "mode": RiverAnimal.Mode.REST, "aux": 4, "facing": PI * 0.65, "elapsed": 0.4},
		]
		for idx: int in poses.size():
			var cfg: Dictionary = poses[idx]
			var ra: RiverAnimal = load("res://src/water/river_animal.tscn").instantiate() as RiverAnimal
			ra.name = "PreviewRiver%d" % idx
			ra.kind = String(cfg["kind"])
			ra.school = String(cfg["school"])
			ra.member = int(cfg.get("member", 0))
			ra.home = cfg["pos"] as Vector2
			ra.position = ra.home
			rpop.animals.add_child(ra)
			ra.set_physics_process(false)
			var end_pt: Vector2 = ra.position + (Vector2.from_angle(float(cfg["facing"])) * 16.0 if int(cfg["mode"]) == RiverAnimal.Mode.TRAVEL else Vector2.ZERO)
			ra._act(int(cfg["mode"]), ra.position, end_pt, Vector2.ZERO, 2.8, float(cfg["facing"]), float(cfg["elapsed"]), int(cfg["aux"]))
			ra._moving = false
			ra._process(0.0)
	elif birds_mode:
		var bpop: WoodlandPopulation = world.get_node("Wildlife/Woodland") as WoodlandPopulation
		bpop.set_process(false)
		for ex_m: Node in bpop._residents.get_children():
			ex_m.queue_free()
		var cpop_b: CorvidPopulation = world.get_node("Wildlife/Corvids") as CorvidPopulation
		cpop_b.set_process(false)
		for ex_b: Node in cpop_b._birds.get_children():
			ex_b.queue_free()
		await get_tree().process_frame
		# Pick up to two nearby visible FirTrees so woodpeckers cling to real trunks in-world
		var near_trees: Array[FirTree] = []
		for node: Node in get_tree().get_nodes_in_group("trees"):
			var tree: FirTree = node as FirTree
			if tree != null and tree.visible and tree.global_position.distance_to(center) < 130.0:
				near_trees.append(tree)
		near_trees.sort_custom(func(a: FirTree, b: FirTree) -> bool: return a.global_position.distance_to(center) < b.global_position.distance_to(center))
		var focus: Vector2 = near_trees[0].global_position + Vector2(0, 14) if not near_trees.is_empty() else center
		if not capture.is_empty():
			for child: Node in world.get_children():
				if child is Camera2D:
					(child as Camera2D).position = focus
		# 1. Buntspecht drumming on real FirTree trunk + Schwarzspecht clinging on 2nd trunk + Grünspecht in Wellenflug dart
		var wp0: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		wp0.name = "PreviewWoodpecker0"
		wp0.species = "woodpecker"
		wp0.appearance = 0
		if not near_trees.is_empty():
			wp0.position = near_trees[0].global_position + Vector2(-4.0, 0.5)
			wp0._perch_path = String(near_trees[0].get_path())
		else:
			wp0.position = focus + Vector2(-36, -12)
		wp0.home = wp0.position
		wp0.facing = 0.0
		cpop_b._birds.add_child(wp0)
		wp0.set_physics_process(false)
		wp0._height = 14.0
		wp0.state = WildCorvid.State.PECK
		wp0._elapsed = 0.22
		wp0._process(0.05)

		var wp1: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		wp1.name = "PreviewWoodpecker1"
		wp1.species = "woodpecker"
		wp1.appearance = 1
		if near_trees.size() >= 2:
			wp1.position = near_trees[1].global_position + Vector2(4.0, 0.5)
			wp1._perch_path = String(near_trees[1].get_path())
		elif not near_trees.is_empty():
			wp1.position = near_trees[0].global_position + Vector2(4.0, 0.5)
			wp1._perch_path = String(near_trees[0].get_path())
		else:
			wp1.position = focus + Vector2(38, -14)
		wp1.home = wp1.position
		wp1.facing = PI
		cpop_b._birds.add_child(wp1)
		wp1.set_physics_process(false)
		wp1._height = 20.0
		wp1.state = WildCorvid.State.WATCH
		wp1._elapsed = 0.4
		wp1._process(0.0)

		var wp2: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		wp2.name = "PreviewWoodpecker2"
		wp2.species = "woodpecker"
		wp2.appearance = 2
		wp2.position = focus + Vector2(-8, -6)
		wp2.home = wp2.position
		wp2.facing = PI * 0.12
		cpop_b._birds.add_child(wp2)
		wp2.set_physics_process(false)
		wp2._height = 22.0
		wp2.state = WildCorvid.State.FLY
		wp2._duration = 2.0
		wp2._elapsed = 0.92
		wp2._process(0.0)

		# 2. Eichelhäher: caching acorn (PECK) + crest-raised Räätsch! sentinel (WATCH + call_pose) + blue-wing hop
		var jay0: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		jay0.name = "PreviewJayAcorn"
		jay0.species = "jay"
		jay0.appearance = 0
		jay0.position = focus + Vector2(-48, 22)
		jay0.home = jay0.position
		jay0.facing = PI * 0.16
		cpop_b._birds.add_child(jay0)
		jay0.set_physics_process(false)
		jay0.state = WildCorvid.State.PECK
		jay0._elapsed = 0.35
		jay0._process(0.0)

		var jay1: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		jay1.name = "PreviewJaySentinel"
		jay1.species = "jay"
		jay1.appearance = 1
		jay1.position = focus + Vector2(44, 14)
		jay1.home = jay1.position
		jay1.facing = PI * 0.78
		cpop_b._birds.add_child(jay1)
		jay1.set_physics_process(false)
		jay1._height = 10.0
		jay1.state = WildCorvid.State.WATCH
		jay1._call_pose = 0.3
		jay1._elapsed = 0.3
		jay1._process(0.0)

		var jay2: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		jay2.name = "PreviewJayFlight"
		jay2.species = "jay"
		jay2.appearance = 2
		jay2.position = focus + Vector2(22, -2)
		jay2.home = jay2.position
		jay2.facing = PI * 0.75
		cpop_b._birds.add_child(jay2)
		jay2.set_physics_process(false)
		jay2._height = 16.0
		jay2.state = WildCorvid.State.FLY
		jay2._duration = 2.0
		jay2._elapsed = 0.65
		jay2._process(0.0)

		# 3. Rotkehlchen: following rooting wild boar sow for worms + singing from perch + puffed ball
		var sow_b: WoodlandMammal = _make(bpop, "boar", 0, focus + Vector2(-14, 30))
		sow_b.set_physics_process(false)
		sow_b.facing = PI * 0.14
		sow_b._visual_facing = sow_b.facing
		sow_b._issue(WoodlandMammal.Mood.FORAGE, 3.0, sow_b.facing, 0.8)

		var rob0: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		rob0.name = "PreviewRobinWorm"
		rob0.species = "robin"
		rob0.appearance = 0
		rob0.position = sow_b.position + Vector2(24, 6)
		rob0.home = rob0.position
		rob0.facing = PI * 0.86
		cpop_b._birds.add_child(rob0)
		rob0.set_physics_process(false)
		rob0.state = WildCorvid.State.PECK
		rob0._elapsed = 0.25
		rob0._process(0.0)

		var rob1: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		rob1.name = "PreviewRobinSing"
		rob1.species = "robin"
		rob1.appearance = 1
		rob1.position = focus + Vector2(30, 34)
		rob1.home = rob1.position
		rob1.facing = PI * 0.72
		cpop_b._birds.add_child(rob1)
		rob1.set_physics_process(false)
		rob1._height = 8.0
		rob1.state = WildCorvid.State.IDLE
		rob1._call_pose = 0.3
		rob1._elapsed = 0.2
		rob1._process(0.0)

		var rob2: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		rob2.name = "PreviewRobinPuffed"
		rob2.species = "robin"
		rob2.appearance = 2
		rob2.position = focus + Vector2(-30, 38)
		rob2.home = rob2.position
		rob2.facing = PI * 0.22
		cpop_b._birds.add_child(rob2)
		rob2.set_physics_process(false)
		rob2.state = WildCorvid.State.IDLE
		rob2._elapsed = 0.4
		rob2._process(0.0)
	elif hex_mode:
		var hpop: WoodlandPopulation = world.get_node("Wildlife/Woodland") as WoodlandPopulation
		hpop.set_process(false)
		var cpop: CorvidPopulation = world.get_node("Wildlife/Corvids") as CorvidPopulation
		cpop.set_process(false)
		var goat_black: WoodlandMammal = _make(hpop, "hex_goat", 0, center + Vector2(-58, -8))
		goat_black.set_physics_process(false)
		goat_black.facing = PI * 0.18
		goat_black._visual_facing = goat_black.facing
		goat_black._issue(WoodlandMammal.Mood.REAR, 1.4, goat_black.facing, 0.55)
		var goat_pale: WoodlandMammal = _make(hpop, "hex_goat", 1, center + Vector2(-18, 18))
		goat_pale.set_physics_process(false)
		goat_pale.facing = PI * 0.65
		goat_pale._visual_facing = goat_pale.facing
		goat_pale._issue(WoodlandMammal.Mood.ALERT, 3.0, goat_pale.facing, 0.4)
		var goat_kid: WoodlandMammal = _make(hpop, "hex_goat", 3, center + Vector2(12, 26))
		goat_kid.set_physics_process(false)
		goat_kid.facing = PI * 0.72
		goat_kid._visual_facing = goat_kid.facing
		goat_kid._issue(WoodlandMammal.Mood.REST, 3.0, goat_kid.facing, 0.2)
		var toad_sac: WoodlandMammal = _make(hpop, "hex_toad", 0, center + Vector2(54, 14))
		toad_sac.set_physics_process(false)
		toad_sac.facing = PI * 0.78
		toad_sac._visual_facing = toad_sac.facing
		toad_sac._issue(WoodlandMammal.Mood.BARK, 1.2, toad_sac.facing, 0.55)
		var toad_tongue: WoodlandMammal = _make(hpop, "hex_toad", 1, center + Vector2(32, -16))
		toad_tongue.set_physics_process(false)
		toad_tongue.facing = PI * 0.12
		toad_tongue._visual_facing = toad_tongue.facing
		toad_tongue._issue(WoodlandMammal.Mood.SPECIAL, 0.85, toad_tongue.facing, 0.36)
		var toad_pale: WoodlandMammal = _make(hpop, "hex_toad", 2, center + Vector2(78, -6))
		toad_pale.set_physics_process(false)
		toad_pale.facing = PI * 0.68
		toad_pale._visual_facing = toad_pale.facing
		toad_pale._issue(WoodlandMammal.Mood.ALERT, 2.0, toad_pale.facing, 0.3)
		var owl_hex: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		owl_hex.name = "PreviewHexOwl"
		owl_hex.species = "owl"
		owl_hex.appearance = 2
		owl_hex.witch = true
		owl_hex.position = center + Vector2(-8, -26)
		owl_hex.home = owl_hex.position
		owl_hex.facing = PI * 0.35
		cpop._birds.add_child(owl_hex)
		owl_hex.set_physics_process(false)
		owl_hex._height = 24.0
		owl_hex.state = WildCorvid.State.WATCH
		owl_hex._call_pose = 0.25
		owl_hex._process(0.0)
	else:
		var population: WoodlandPopulation = world.get_node("Wildlife/Woodland") as WoodlandPopulation
		population.set_process(false)
		var cpop2: CorvidPopulation = world.get_node("Wildlife/Corvids") as CorvidPopulation
		cpop2.set_process(false)
		# Wild boar sounder (keiler + sow + striped piglet)
		var keiler: WoodlandMammal = _make(population, "boar", 1, center + Vector2(-118, 66))
		keiler.set_physics_process(false)
		keiler.facing = PI * 0.18
		keiler._visual_facing = keiler.facing
		keiler._issue(WoodlandMammal.Mood.BARK, 1.2, keiler.facing, 0.45)
		var sow: WoodlandMammal = _make(population, "boar", 0, center + Vector2(-78, 86))
		sow.set_physics_process(false)
		sow.facing = PI * 0.15
		sow._visual_facing = sow.facing
		sow._issue(WoodlandMammal.Mood.FORAGE, 3.0, sow.facing, 0.8)
		var piglet: WoodlandMammal = _make(population, "boar", 2, center + Vector2(-102, 102))
		piglet.set_physics_process(false)
		piglet.facing = PI * 0.15
		piglet._visual_facing = piglet.facing
		piglet._issue(WoodlandMammal.Mood.REST, 3.0, piglet.facing, 0.2)
		# Lynx stalking / watching
		var lynx: WoodlandMammal = _make(population, "lynx", 0, center + Vector2(-12, 68))
		lynx.set_physics_process(false)
		lynx.facing = PI * 0.24
		lynx._visual_facing = lynx.facing
		lynx._issue(WoodlandMammal.Mood.ALERT, 3.0, lynx.facing, 0.4)
		# Badger + real burrow den
		var den: WildlifeShelter = load("res://src/entities/wildlife/wildlife_shelter.tscn").instantiate() as WildlifeShelter
		den.name = "PreviewDen"
		den.position = center + Vector2(68, 66)
		population.get_node("Shelters").add_child(den)
		var badger: WoodlandMammal = _make(population, "badger", 0, center + Vector2(56, 82))
		badger.set_physics_process(false)
		badger.facing = PI * 0.72
		badger._visual_facing = badger.facing
		badger._issue(WoodlandMammal.Mood.SPECIAL, 2.5, badger.facing, 0.5)
		# Red squirrel gnawing spruce cone + black squirrel climbing
		var sq_cone: WoodlandMammal = _make(population, "squirrel", 0, center + Vector2(-34, 114))
		sq_cone.set_physics_process(false)
		sq_cone.facing = PI * 0.22
		sq_cone._visual_facing = sq_cone.facing
		sq_cone._issue(WoodlandMammal.Mood.SPECIAL, 3.0, sq_cone.facing, 0.6)
		var sq_climb: WoodlandMammal = _make(population, "squirrel", 2, center + Vector2(24, 114))
		sq_climb.set_physics_process(false)
		sq_climb.facing = -PI * 0.4
		sq_climb._visual_facing = sq_climb.facing
		sq_climb._climb_action(WoodlandMammal.Mood.CLIMB, sq_climb.position, 1.0, 0.0, 18.0)
		sq_climb._elapsed = 0.55
		# Eagle-Owl perched
		var owl_w: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
		owl_w.name = "PreviewWoodOwl"
		owl_w.species = "owl"
		owl_w.appearance = 0
		owl_w.position = center + Vector2(88, 108)
		owl_w.home = owl_w.position
		owl_w.facing = PI * 0.75
		cpop2._birds.add_child(owl_w)
		owl_w.set_physics_process(false)
		owl_w._height = 22.0
		owl_w.state = WildCorvid.State.PECK
		owl_w._elapsed = 1.2
		owl_w._process(0.0)
	if not capture.is_empty():
		for frame: int in 12:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var error: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("Woodland capture: ", error_string(error))
		get_tree().quit(error)
