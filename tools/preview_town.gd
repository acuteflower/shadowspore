extends Node
## The town in the real world. `-- --capture=/abs/file.png [--night] [--ghost] [--site] [--zoom=2]` founds the town beside the hut, builds a few pieces at once (lamp posts, a bench, a
## fence, plates, the stockpile and the workshop), lets Gustav settle at her bench and saves a screenshot; --ghost shows the build mode with a piece on a free spot,
## --site leaves the workshop as a half-built site. Offline, no save access. Without --capture you can walk and press B.

func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 18):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 8.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


func _put(town: TownManager, piece: String, pos: Vector2, flip: bool = false, finish: bool = true) -> int:
	town._host_place(piece, pos, 1 if flip else 0, 1)
	var id: int = town.next_id - 1
	if finish and town.structures.has(id):
		(town.structures[id] as Dictionary).g = TownManager.PROGRESS_FULL
		town._rpc_done(id)
	return id


func _run() -> void:
	var capture: String = ""
	var night: bool = false
	var ghost: bool = false
	var site: bool = false
	var tab: bool = false
	var craft: bool = false
	var stock: bool = false
	var demolish: bool = false
	var shop_tab: int = 0 ## --craft --tab=N: which tab of the workbench
	var valdric_at: float = -1.0 ## --valdric=0.45: the time of day to show Valdric at (repair 0.45, fire 0.54, practice 0.62, guard 0.74, night 0.95 ...)
	var lamps: bool = false ## --lamps: four lamp posts at 25, 50, 75 and 100 % of the build
	var south: bool = false ## --ghost --south: aim the piece at the ground behind the menu (it dims)
	var category: int = 0 ## --ghost --cat=N: which category of the build menu (--demolish shows the tool)
	var walk_at: float = 0.0006 ## of a day after the plan changed
	var early: bool = false ## --craft --early: the picture while the board is still growing in
	var critter: String = "" ## --crow / --fox: a visiting animal (waits until it has landed / sniffs at the stockpile)
	var aged: bool = false ## --aged: every piece has stood six days (all the wear shows)
	var old_hut: bool = false ## --oldhut: like --hut, but the hut stays broken
	var hut_view: bool = false ## --hut: the renewed hut with its window light, the camera in front of it
	var smithy_view: bool = false ## --smithy: Torben's smithy next to the workshop, the camera in front of it (add --night, --aged)
	var forge_window: bool = false ## --forge (with --tab=N): Torben's shop window opens at tab N (4 = VERFEINERN) with a weapon, material and money in the bag
	var walk: bool = false ## Gustav on his way from the bench to the fire (a quarter of the way round the workshop)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture = arg.get_slice("=", 1)
		elif arg == "--night": night = true
		elif arg == "--ghost": ghost = true
		elif arg == "--demolish": demolish = true
		elif arg == "--site": site = true
		elif arg == "--tab": tab = true
		elif arg == "--craft": craft = true
		elif arg == "--stock": stock = true
		elif arg == "--walk": walk = true
		elif arg == "--hut": hut_view = true
		elif arg == "--aged": aged = true
		elif arg == "--crow": critter = "crow"
		elif arg == "--fox": critter = "fox"
		elif arg == "--oldhut": hut_view = true; old_hut = true
		elif arg == "--early": early = true
		elif arg == "--south": south = true
		elif arg == "--smithy": smithy_view = true
		elif arg == "--forge": smithy_view = true; forge_window = true
		elif arg == "--lamps": lamps = true
		elif arg.begins_with("--valdric="): valdric_at = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--tab="): shop_tab = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--cat="): category = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--at="): walk_at = arg.get_slice("=", 1).to_float()
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	player.request_teleport(hut.position + Vector2(20, 150))
	await _frames(120)
	player.quests.set_flag("rebuild_done")
	await _frames(70)
	for item: String in ["wood", "stone", "glow_cap", "plant_fiber", "plank", "iron_ore"]:
		player.inventory.give(item, 90)
	var lamp: Vector2 = _site(town, "lamp_post", hut.position + Vector2(-80, 120))
	_put(town, "lamp_post", lamp)
	var lamp2: Vector2 = _site(town, "lamp_post", hut.position + Vector2(150, 140))
	_put(town, "lamp_post", lamp2)
	await _frames(3)
	if smithy_view: ## the workshop and the smithy wait for their residents
		town.residents["gustav"] = {"trust": 0, "talked": -1}
		if not forge_window:
			town.residents["torben"] = {"trust": 0, "talked": -1}
	var shop: Vector2 = _site(town, "workshop", hut.position + Vector2(40, 175))
	_put(town, "workshop", shop, false, not site)
	var store: Vector2 = _site(town, "stockpile", hut.position + Vector2(-110, 190))
	_put(town, "stockpile", store)
	for k: int in 6:
		var plate: Vector2 = TownRules.snapped_position("path_stone", hut.position + Vector2(20 + k * 16, 118))
		if town.check_site("path_stone", plate) == "":
			_put(town, "path_stone", plate)
	for k: int in 4:
		var fence: Vector2 = TownRules.snapped_position("fence", store + Vector2(-60 + k * 24, 20))
		if town.check_site("fence", fence) == "":
			_put(town, "fence", fence, k % 2 == 1)
	var bench: Vector2 = _site(town, "bench", hut.position + Vector2(80, 100))
	_put(town, "bench", bench)
	var forge: Vector2 = Vector2.INF
	if smithy_view:
		forge = _site(town, "smithy", hut.position + Vector2(150, 205))
		print("smithy at ", forge - hut.position, " check ", town.check_site("smithy", forge))
		_put(town, "smithy", forge)
	await _frames(3)
	if not site:
		await _frames(900)
	if night:
		TimeManager.time_of_day = 0.96
	else:
		TimeManager.time_of_day = 0.5
	player.request_teleport((forge + Vector2(-10, 30)) if smithy_view and forge != Vector2.INF else shop + Vector2(10, 40))
	if ghost:
		await _frames(30)
		var builder: BuildMode = town.build_mode()
		InputManager.using_mouse = false
		builder.set_active(true)
		builder.select("lamp_post")
		player.facing = Vector2(1, 0.6) if south else Vector2(1, -0.4)
	await _frames(120)
	if ghost:
		var builder: BuildMode = town.build_mode()
		builder.category = category
		builder.select(builder.pieces_here()[0])
		var near: Vector2 = _site(town, "lamp_post", player.global_position + Vector2(52, 20))
		builder._update_ghost(near)
		builder.queue_redraw()
		await _frames(3)
		builder._update_ghost(near)
		builder.set_demolish(demolish)
	if tab:
		var pause: PauseMenu = player.get_node("Hud/PauseMenu") as PauseMenu
		pause._set_open(true)
		pause._select_tab(2)
		await _frames(120)
	if craft:
		player.request_teleport(shop + Vector2(-30, 44))
		await _frames(20)
		var shop_window: ShopWindow = ShopWindow.open(get_tree(), player, town, "gustav_bench")
		if shop_tab > 0:
			shop_window._set_tab(shop_tab)
		await _frames(28 if early else 110)
	if forge_window:
		TimeManager.locked = true
		TimeManager.time_of_day = 0.4
		town._rpc_resident.rpc("torben", {"trust": 60, "talked": -1}, false) ## he moves in properly (a figure at his anvil)
		await _frames(10)
		for item: String in ["iron_plate", "void_splinter", "iron_ingot"]:
			player.inventory.give(item, 5)
		player.progress.award(900, 0)
		player.inventory.give("sword_iron", 1, {"r": 7, "rp": 2})
		player.inventory.give("sword_basic", 1, {"r": 3})
		player.inventory.give("sword_void", 1)
		player.request_teleport(forge + Vector2(-10, 60))
		await _frames(240)
		var forge_shop: ShopWindow = ShopWindow.open(get_tree(), player, town, "torben_forge")
		forge_shop._set_tab(shop_tab if shop_tab > 0 else 4)
		await _frames(110)
	if stock:
		player.request_teleport(store + Vector2(0, 40))
		await _frames(30)
		town.request_stock("deposit_all", "", 0)
		await _frames(5)
		StockWindow.open(get_tree(), player, town, store + Vector2(0, -20))
		await _frames(110)
	if walk:
		var gustav: Settler = town.settler_node("gustav")
		TimeManager.locked = true
		TimeManager.time_of_day = 0.76 + walk_at
		await _frames(20)
		player.request_teleport(gustav.global_position + Vector2(60, 50))
		await _frames(60)
		print("gustav at ", gustav.global_position - shop, " route ", town.walk_route(town.settler_node("gustav").spot_position("work"), town.settler_node("gustav").spot_position("fire")))
	if valdric_at >= 0.0:
		TimeManager.locked = true
		TimeManager.time_of_day = valdric_at
		await _frames(30)
		var valdric: Settler = town.settler_node("valdric")
		if valdric != null:
			player.request_teleport(valdric.global_position + Vector2(40, 36))
			await _frames(90)
			print("valdric at ", valdric.global_position - hut.position, " spot ", valdric._spot, " clip ", valdric._clip)
	if lamps:
		var ids: Array[int] = []
		player.request_teleport(hut.position + Vector2(20, 215))
		for k: int in 4:
			var lamp_id: int = town.next_id
			town.next_id += 1
			var lamp_at: Vector2 = hut.position + Vector2(-60 + k * 52, 170)
			town._rpc_added(lamp_id, {"p": "lamp_post", "x": lamp_at.x, "y": lamp_at.y, "f": 0, "g": [250, 500, 750, 0][k]}, [])
			ids.append(lamp_id)
		await _frames(2)
		town.set_physics_process(false) ## nobody builds: the sites stay at their stage
		for k: int in ids.size():
			if k == 3:
				(town.structures[ids[k]] as Dictionary).g = 1000
				town._rpc_done(ids[k])
		await _frames(150)
	if aged:
		for sid: Variant in town.structures:
			(town.structures[sid] as Dictionary).b = TimeManager.day - 6
		await _frames(100)
	if critter != "":
		var visitor: Node = town.critters.debug_visit(critter)
		await _frames(900 if critter == "crow" else 1500)
		print("visitor ", visitor, " ", visitor.global_position if visitor != null and is_instance_valid(visitor) else "gone")
	if hut_view:
		hut.set_renewed(not old_hut)
		player.request_teleport(hut.position + Vector2(40, 52))
		await _frames(40)
	if "--nosmall" in OS.get_cmdline_user_args(): ## experiment: only the big lights (the per-item light limit)
		for n: Node in get_tree().get_nodes_in_group("night_lights"):
			var small: NightLight = n as NightLight
			if small != null and small.radius <= 34 and not (small.get_parent() is Hut):
				small.set_process(false)
				small.enabled = false
				small.set_night(0.0)
				small.set_script(null)
		await _frames(10)
	if capture != "":
		for n: Node in get_tree().get_nodes_in_group("night_lights"):
			var nl: NightLight = n as NightLight
			if nl != null and nl.enabled and nl.global_position.distance_to(hut.position) < 260.0:
				print("LIGHTS ", nl.get_parent().name, " rel ", nl.global_position - hut.position, " r ", nl.radius, " e ", nl.energy, " tex ", nl.texture.get_size(), " scale ", nl.texture_scale, " color ", nl.color)
		for v: Variant in town._views.values():
			var view: TownStructure = v as TownStructure
			for pt: Dictionary in view._parts:
				var spr: Sprite2D = pt.sprite as Sprite2D
				print("part ", view.piece, " ", spr.texture.resource_path, " vis ", spr.visible, " pos ", spr.position, " size ", spr.texture.get_size(), " mat ", spr.material != null, " gpos ", spr.global_position)
		for v2: Variant in town._views.values():
			var view2: TownStructure = v2 as TownStructure
			print("VIEW ", view2.piece, " at ", view2.global_position - hut.position, " visible ", view2.visible, " sprite ", view2._sprite.texture.get_size() if view2._sprite != null and view2._sprite.texture != null else "none")
		await _frames(4)
		get_viewport().get_texture().get_image().save_png(capture)
		print("saved ", capture, " town pieces: ", town.structures.size(), " residents: ", town.residents.keys(), " ways (points, joined): ", town.paths.map(func(w: Variant) -> String: return "%d/%s" % [((w as Dictionary).p as Array).size(), "door" if int((w as Dictionary).e) == 1 else "joined"]))
		get_tree().quit()
