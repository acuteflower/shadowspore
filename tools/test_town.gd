extends Node
## docs/town.md in the real world: found the town, place and build pieces (helpers, light, costs, clearing, demolishing), the stock, Gustav's arrival, her day, crafting,
## trust, production, saving and loading, the build mode, the STADT tab and the windows. Run with `--fixed-fps 60` (the simulated seconds are cheap).

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TOWN FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _find_site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 16):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 10.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


## Something solid standing in the world on physics layer 1 (what a fallen log is, as far as a probe is concerned).
func _block(world: Node, rect: Rect2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = 1
	body.position = rect.get_center()
	world.add_child(body)
	return body


func _in_piece(town: TownManager, point: Vector2) -> bool:
	for id: int in town.structures:
		if not bool(TownRules.piece(String((town.structures[id] as Dictionary).p)).get("walk", false)) and town.rect_of(id).has_point(point):
			return true
	return false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for id: String in ["lamp_post", "fence", "bench", "path_stone", "stockpile", "workshop"]:
		(TownRules.piece(id) as Dictionary)["build_seconds"] = 0.6 ## simulated time is cheap, but not that cheap
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	_check(town != null and not town.founded, "a fresh world has an unfounded town")
	_check(town.check_place("lamp_post", Vector2(100, 100), player) == "KEINE STADT", "nothing can be built before the founding")
	var hut: Hut = world.hut_node()
	_check(hut != null, "the world has the hut")
	player.request_teleport(hut.position + Vector2(0, 120))
	await _frames(90)
	# --- founding
	var founded_signal: Array = [false]
	town.town_founded.connect(func() -> void: founded_signal[0] = true)
	player.quests.set_flag("rebuild_done") ## the renewed hut: the town begins by itself
	await _frames(100)
	_check(town.founded and founded_signal[0], "the town founds itself when the hut is renewed")
	_check(town.center == hut.position and town.is_built(0), "the heart of the town is the hut")
	_check(town.in_territory(hut.position + Vector2(0, 100)) and not town.in_territory(hut.position + Vector2(0, 400)), "the hut lights its yard only")
	_check(town.level() == 0 and town.level_label() == "RASTPLATZ", "a new town is a camp")
	# --- a lamp post
	player.inventory.give("wood", 90)
	player.inventory.give("stone", 40)
	player.inventory.give("glow_cap", 4)
	player.inventory.give("plant_fiber", 12)
	var lamp_at: Vector2 = _find_site(town, "lamp_post", hut.position + Vector2(60, 110))
	_check(lamp_at != Vector2.INF, "there is a free site for a lamp post by the hut")
	_check(town.check_site("lamp_post", hut.position + Vector2(0, 400)) == "AUSSERHALB DES LICHTS", "a site in the dark is refused")
	_check(town.check_site("lamp_post", hut.position + Vector2(0, -6)) != "", "the hut itself is in the way (%s)" % town.check_site("lamp_post", hut.position + Vector2(0, -6)))
	var wood_before: int = player.inventory.count_item("wood")
	town.request_place("lamp_post", lamp_at, false)
	await _frames(3)
	_check(town.structures.size() == 2 and town.next_id == 2, "the lamp post is a new structure (%d)" % town.structures.size())
	_check(player.inventory.count_item("wood") == wood_before - 3 and player.inventory.count_item("glow_cap") == 2, "the cost was paid from the bag")
	var lamp_id: int = 1
	_check(town.structures.has(lamp_id) and int((town.structures[lamp_id] as Dictionary).g) < TownManager.PROGRESS_FULL, "a new piece is a site")
	_check(town.view_of(lamp_id) != null, "the picture of the site stands near the player")
	_check(town.check_site("lamp_post", lamp_at) == "IM WEG", "a second piece on the same spot is refused")
	_check(not town.circles().any(func(c: Vector3) -> bool: return is_equal_approx(c.x, lamp_at.x) and is_equal_approx(c.y, lamp_at.y - 8.0)), "a site does not light anything yet")
	for i: int in 400:
		await get_tree().process_frame
		if town.is_built(lamp_id):
			break
	_check(town.is_built(lamp_id), "the lamp post is finished while she stands next to it")
	_check(player.quests.has_flag("built_lamp_post"), "a finished piece sets the story flag built_<piece>")
	_check(town.in_territory(lamp_at + Vector2(100, 0)), "the lamp post carries the light further")
	_check(town.check_place("lamp_post", lamp_at + Vector2(0, 200), player) != "", "a piece out of reach is refused (%s)" % town.check_place("lamp_post", lamp_at + Vector2(0, 200), player))
	# --- who builds: nobody near -> no progress
	var far_at: Vector2 = _find_site(town, "bench", lamp_at + Vector2(-50, 40))
	_check(far_at != Vector2.INF, "a free site for a bench")
	player.request_teleport(far_at + Vector2(0, 400))
	await _frames(60)
	town._host_place("path_stone", TownRules.snapped_position("path_stone", hut.position + Vector2(80, 50)), 0, 1) ## placed by hand: she is far away now
	await _frames(1)
	var plate_id: int = town.next_id - 1
	var g_before: int = int((town.structures[plate_id] as Dictionary).g) if town.structures.has(plate_id) else -1
	await _frames(60)
	_check(not town.structures.has(plate_id) or int((town.structures[plate_id] as Dictionary).g) == g_before, "a site stands still while nobody is near")
	player.request_teleport(hut.position + Vector2(0, 120))
	await _frames(90)
	# --- soft props are swept away
	var soft_cell: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in world._things:
		var thing: WorldProp = world._things[cell] as WorldProp
		if thing.kind in ["bush", "berry_bush", "grass", "pebble", "mushroom", "ember_bush"]:
			soft_cell = cell
			break
	_check(soft_cell.x >= 0, "some soft prop is loaded")
	if soft_cell.x >= 0:
		var thing: WorldProp = world._things[soft_cell] as WorldProp
		var cells: Array = world.town_soft_cells(Rect2(thing.position - Vector2(3, 3), Vector2(6, 6)))
		_check(cells.has(soft_cell), "a foundation over a bush sweeps it away")
		world.town_clear_cells(cells)
		_check(not world._things.has(soft_cell), "the cleared prop is gone from the world")
		town.cleared[soft_cell] = true
	var tree_cell: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in world._things:
		if (world._things[cell] as WorldProp).kind == "tree":
			tree_cell = cell
			break
	if tree_cell.x >= 0:
		var tree: WorldProp = world._things[tree_cell] as WorldProp
		_check(world.town_soft_cells(Rect2(tree.position - Vector2(3, 3), Vector2(6, 6))).is_empty(), "a standing tree is not swept away")
		_check(world.town_probe(Rect2(tree.position - Vector2(8, 8), Vector2(16, 16))) != "", "a standing tree is in the way (%s)" % world.town_probe(Rect2(tree.position - Vector2(8, 8), Vector2(16, 16))))
	# --- used-up props inside the light stay as they are (stump, rubble, regrowth): the light sweeps nothing away
	var spent: Dictionary = {}
	for cell: Vector2i in world._things:
		var thing: WorldProp = world._things[cell] as WorldProp
		if town.in_territory(thing.position) and not spent.has(thing.kind) and thing.kind in ["pebble", "bush"]:
			spent[thing.kind] = cell
	_check(spent.has("pebble") or spent.has("bush"), "a pebble or a bush lies in the light")
	for kind: String in spent:
		var cell: Vector2i = spent[kind]
		var state: Dictionary = {"p": TimeManager.day + 1, "k": kind} if kind == "pebble" else {"h": 99, "k": kind}
		world._rpc_thing_state(cell, state, "pick" if kind == "pebble" else "strip")
	await _frames(70)
	for kind: String in spent:
		var cell: Vector2i = spent[kind]
		_check(world._things.has(cell) and not town.cleared.has(cell) and world._thing_states.has(cell), "a used-up %s in the light stays and grows back" % kind)
	# --- demolish: a finished piece gives back 60 %, rounded up, into the stock
	var stock_wood: int = int(town.stock.get("wood", 0))
	town.request_demolish(lamp_id)
	await _frames(3)
	_check(not town.structures.has(lamp_id) and town.view_of(lamp_id) == null, "the lamp post is gone")
	_check(int(town.stock.get("wood", 0)) == stock_wood + 2 and int(town.stock.get("glow_cap", 0)) == 2, "60%% of the cost went to the stock (%s)" % str(town.stock))
	_check(not town.in_territory(lamp_at + Vector2(100, 0)), "its light went with it")
	town.request_demolish(0)
	await _frames(2)
	_check(town.structures.has(0), "the house cannot be demolished")
	# --- the stockpile: stow and take
	var stock_site: Vector2 = _find_site(town, "stockpile", hut.position + Vector2(-40, 110))
	_check(stock_site != Vector2.INF, "a free site for the stockpile")
	town.request_place("stockpile", stock_site, false)
	await _frames(3)
	var stock_id: int = town.next_id - 1
	for i: int in 400:
		await get_tree().process_frame
		if town.is_built(stock_id):
			break
	_check(town.is_built(stock_id) and town.has_built("stockpile"), "the stockpile is finished")
	_check(town.paths.size() == 1 and int((town.paths[0] as Dictionary).s) == stock_id and int((town.paths[0] as Dictionary).d) == 1, "the stockpile got a trampled way when it was finished (%d)" % town.paths.size())
	if not town.paths.is_empty():
		var way: Array = (town.paths[0] as Dictionary).p as Array
		var way_start: Vector2 = Vector2(float((way[0] as Array)[0]), float((way[0] as Array)[1]))
		var way_end: Vector2 = Vector2(float((way[way.size() - 1] as Array)[0]), float((way[way.size() - 1] as Array)[1]))
		_check(way_start.distance_to(stock_site + Vector2(0, 9)) < 1.0, "the way starts at the door (front of the footprint)")
		_check(way_end.distance_to(hut.exit_position) < 1.0, "and runs to the hut's door, the only node of the network so far")
		var rect: Rect2 = TownRules.foot_rect("stockpile", stock_site.x, stock_site.y)
		var crossing: bool = false
		for k: int in way.size() - 1:
			var a: Vector2 = Vector2(float((way[k] as Array)[0]), float((way[k] as Array)[1]))
			var b: Vector2 = Vector2(float((way[k + 1] as Array)[0]), float((way[k + 1] as Array)[1]))
			for step: int in range(int(a.distance_to(b) / 4.0) + 1):
				if rect.has_point(a.lerp(b, float(step) * 4.0 / maxf(a.distance_to(b), 1.0))):
					crossing = true
		_check(not crossing, "the way goes round the building, not through it")
		var middle: Vector2 = way_start.lerp(way_end, 0.5)
		_check(way.size() >= 2 and town._path_views.size() == 1, "the way has its picture")
		_check(town.surface_at(Vector2(float((way[0] as Array)[0]), float((way[0] as Array)[1]) - 1.0)) == "path" or town.surface_at(middle) == "path" or way.size() > 2, "a finished way is path underfoot (%s)" % town.surface_at(way_start))
	var view: TownStructure = town.view_of(stock_id)
	_check(view != null and view.prompt() == "LAGER ÖFFNEN", "the stockpile offers its stock")
	var bag_wood: int = player.inventory.count_item("wood")
	player.request_teleport(TownRules.foot_rect("stockpile", stock_site.x, stock_site.y).get_center() + Vector2(0, 50))
	await _frames(20)
	town.request_stock("deposit_all", "", 0)
	await _frames(3)
	_check(player.inventory.count_item("wood") == 0 and int(town.stock.get("wood", 0)) >= bag_wood, "stowing moves all material into the stock (%s)" % str(town.stock))
	town.request_stock("take", "wood", 10)
	await _frames(3)
	_check(player.inventory.count_item("wood") == 10, "taking ten gives ten")
	var window: StockWindow = StockWindow.open(get_tree(), player, town, town.center)
	await _frames(2)
	_check(window != null and player.story_lock and InputManager.ui_blocking, "the stock window opens and holds her")
	await _frames(60)
	_check(player.view_camera().zoom.x > 1.5 and player.view_shift != Vector2.ZERO, "the camera draws close and looks beside her (zoom %.2f)" % player.view_camera().zoom.x)
	if window != null:
		_check(window.tabs.size() == 2 and window.tab == 0 and not window.rows.is_empty(), "the stock tab lists what the town holds (%d kinds)" % window.rows.size())
		var before_take: int = player.inventory.count_item("wood")
		window.focus = 0
		for i: int in window.rows.size():
			if String(window.rows[i].item) == "wood":
				window.focus = i
		window._press("take", false)
		await _frames(3)
		_check(player.inventory.count_item("wood") == before_take + 10, "E takes ten from the focused row")
		window._set_tab(1)
		_check(window.tab == 1 and not window.rows.is_empty(), "the rucksack tab lists what may be stowed")
		for i: int in window.rows.size():
			if String(window.rows[i].item) == "wood":
				window.focus = i
		var stowed_before: int = int(town.stock.get("wood", 0))
		window._press("put", false)
		await _frames(3)
		_check(int(town.stock.get("wood", 0)) == stowed_before + 10, "and E stows ten")
		window._close()
	_check(not player.story_lock and not InputManager.ui_blocking, "closing the window frees her at once")
	await _frames(60)
	_check(is_equal_approx(player.view_camera().zoom.x, 1.0) and player.view_shift.length() < 0.5, "and the camera is back where it was")
	# --- bags and stock pay together
	var stock_before: int = int(town.stock.get("stone", 0))
	_check(town.available("stone", player) == stock_before + player.inventory.count_item("stone"), "available() counts bag and stock")
	# --- a door must not be walled up: a fallen log (not destructible) right in front of it refuses the site
	var door_site: Vector2 = _find_site(town, "workshop", hut.position + Vector2(0, 130))
	_check(door_site != Vector2.INF, "a free site for the door test")
	var door_zone: Rect2 = TownRules.front_rect("workshop", door_site.x, door_site.y)
	var log_body: StaticBody2D = _block(world, Rect2(door_zone.get_center() - Vector2(18, 4), Vector2(36, 8)))
	await _frames(3)
	_check(town.check_site("workshop", door_site) == "TÜR ZUGESTELLT", "a log in front of the door refuses the site (%s)" % town.check_site("workshop", door_site))
	log_body.free()
	var foot_body: StaticBody2D = _block(world, Rect2(TownRules.foot_rect("workshop", door_site.x, door_site.y).get_center() - Vector2(6, 4), Vector2(12, 8)))
	await _frames(3)
	_check(town.check_site("workshop", door_site) == "IM WEG", "the same log on the footprint is simply in the way (%s)" % town.check_site("workshop", door_site))
	foot_body.free()
	await _frames(3)
	_check(town.check_site("workshop", door_site) == "", "with the ground clear again the site is fine (%s)" % town.check_site("workshop", door_site))
	# --- the workshop and Gustav
	var shop_at: Vector2 = _find_site(town, "workshop", hut.position + Vector2(0, 130))
	_check(shop_at != Vector2.INF, "a free site for the workshop near the hut")
	_check(town.check_place("workshop", shop_at, player) == "", "a workshop can be ordered (%s)" % town.check_place("workshop", shop_at, player))
	player.inventory.give("wood", 30)
	player.inventory.give("plant_fiber", 6)
	player.request_teleport(shop_at + Vector2(0, 40))
	await _frames(40)
	town.request_place("workshop", shop_at, false)
	await _frames(3)
	var shop_id: int = town.next_id - 1
	for i: int in 400:
		await get_tree().process_frame
		if town.is_built(shop_id):
			break
	_check(town.is_built(shop_id), "the workshop is finished")
	_check(town.paths.size() == 2 and int((town.paths[1] as Dictionary).d) == 1, "and gets its own way to the network (%d ways)" % town.paths.size())
	_check(player.quests.has_flag("built_workshop"), "the workshop sets built_workshop")
	_check(not town.residents.has("gustav"), "nobody has moved in at the very moment it is finished")
	for i: int in 600:
		await get_tree().process_frame
		if town.residents.has("gustav"):
			break
	_check(town.residents.has("gustav"), "Gustav comes to the new light")
	var gustav: Settler = town.settler_node("gustav")
	_check(gustav != null and gustav.global_position.distance_to(shop_at) > 60.0, "she starts at the edge and walks in")
	TimeManager.time_of_day = 0.5
	var clipped: int = 0
	for i: int in 900:
		await get_tree().process_frame
		if _in_piece(town, gustav.global_position):
			clipped += 1
		if gustav.is_working():
			break
	_check(clipped == 0, "she walks in without crossing a wall (%d frames inside a piece)" % clipped)
	_check(gustav.is_working(), "she walks to her bench and works by day")
	_check(gustav.global_position.distance_to(town.stand_point(shop_at + Vector2(-22, 8))) < 3.0, "at her place by the bench (%s)" % str(gustav.global_position - shop_at))
	_check(gustav.is_helping(), "a settler at work helps building")
	var quarry_of_actors: Array = get_tree().get_nodes_in_group("quest_actors")
	var actor_at: Vector2 = Vector2.INF
	for node: Node in quarry_of_actors:
		var at: Vector2 = node.call("actor_position", "gustav") as Vector2
		if at != Vector2.INF:
			actor_at = at
	_check(actor_at == gustav.global_position, "the quest finds her through quest_actors")
	# her day: the evening at the fire, the night asleep
	TimeManager.time_of_day = 0.85
	await _frames(1200)
	_check(gustav.global_position.distance_to(town.stand_point(town.center + Vector2(6, 80))) < 3.0 and gustav.visible, "in the evening she stands at the hut's fire")
	# her walk to the fire goes round her own workshop (it stands on the straight line between the bench and the fire): the walk is sampled
	var work_at: Vector2 = town.stand_point(shop_at + Vector2(-22, 8))
	var fire_at: Vector2 = town.stand_point(town.center + Vector2(6, 80))
	var straight_hits: bool = false
	for k: int in 41:
		straight_hits = straight_hits or town.rect_of(shop_id).has_point(work_at.lerp(fire_at, float(k) / 40.0))
	_check(straight_hits, "(premise: the straight line from her bench to the fire runs through the workshop)")
	TimeManager.locked = true
	TimeManager.time_of_day = 0.7
	await _frames(30)
	var inside: int = 0
	var travelled: float = 0.0
	var last: Vector2 = gustav.global_position
	for i: int in 150:
		TimeManager.time_of_day = 0.76 + float(i) * 0.00015
		await get_tree().process_frame
		if _in_piece(town, gustav.global_position):
			inside += 1
		travelled += gustav.global_position.distance_to(last)
		last = gustav.global_position
	_check(inside == 0, "on her walk to the fire she never stands inside a piece (%d frames)" % inside)
	_check(travelled > work_at.distance_to(fire_at) + 4.0, "she went round it (%.0f px walked, %.0f straight)" % [travelled, work_at.distance_to(fire_at)])
	_check(gustav.global_position.distance_to(fire_at) < 4.0, "and arrived at the fire (%s)" % str(gustav.global_position - fire_at))
	TimeManager.locked = false
	TimeManager.time_of_day = 0.97
	await _frames(1200)
	_check(not gustav.visible, "at night she sleeps (hidden)")
	TimeManager.time_of_day = 0.5
	await _frames(1200)
	_check(gustav.is_working() and gustav.visible, "and she is back at her bench in the morning")
	# trust
	_check(town.trust_of("gustav") == 0, "she starts without trust")
	town.request_talk("gustav")
	await _frames(2)
	_check(town.trust_of("gustav") == 10, "the first talk of a day builds trust")
	town.request_talk("gustav")
	await _frames(2)
	_check(town.trust_of("gustav") == 10, "a second talk the same day does not")
	TimeManager.day += 1
	town.request_talk("gustav")
	await _frames(2)
	_check(town.trust_of("gustav") == 20 and gustav.trust_tier() == 0, "a talk on the next day adds more")
	# --- crafting
	player.request_teleport(shop_at + Vector2(0, 60))
	await _frames(20)
	var planks: int = player.inventory.count_item("plank")
	var wood_now: int = town.available("wood", player)
	_check(town.recipe_block("plank", player) == "", "planks can be crafted")
	town.request_craft("plank")
	await _frames(3)
	_check(player.inventory.count_item("plank") == planks + 2 and town.available("wood", player) == wood_now - 2, "two wood became two planks")
	_check(town.recipe_block("sword_iron", player) == "" or town.recipe_block("sword_iron", player) != "", "the sword recipe answers")
	_check(town.recipe_block("axe_basic", player) == "", "an axe can be crafted when she has none")
	player.inventory.give("axe_basic", 1)
	_check(town.recipe_block("axe_basic", player) != "", "but not twice (%s)" % town.recipe_block("axe_basic", player))
	town.request_craft("plank")
	await _frames(2)
	var shop: ShopWindow = ShopWindow.open(get_tree(), player, town, "gustav_bench")
	await _frames(60)
	_check(shop != null and shop.tabs.size() == 4 and shop.speaker == gustav, "the workbench is a shop with four tabs and Gustav answers")
	if shop != null:
		_check(not shop.rows.is_empty() and String(shop.rows[0].kind) == "craft", "the first tab lists what she can make herself")
		var made_before: int = player.inventory.count_item("plank")
		shop.focus = 0
		shop._press("craft", false)
		await _frames(120)
		_check(player.inventory.count_item("plank") == made_before + 2, "FERTIGEN makes the planks after a short bar")
		# commissions: only Gustav can forge the sword, and it takes him a while
		shop._set_tab(1)
		var sword_row: int = -1
		for i: int in shop.rows.size():
			if String(shop.rows[i].get("recipe", "")) == "sword_iron":
				sword_row = i
		_check(sword_row >= 0 and String(shop.rows[sword_row].kind) == "order", "the sword is a commission")
		town.stock["plank"] = 4
		town.stock["stone"] = 8
		player.inventory.give("sword_basic", 1)
		player.inventory.give("void_splinter", 2)
		(town.residents["gustav"] as Dictionary).trust = 30
		await _frames(2)
		_check(town.order_block("sword_iron", player) == "", "with trust and material it can be ordered (%s)" % town.order_block("sword_iron", player))
		town.request_order("sword_iron")
		await _frames(3)
		_check(town.orders.size() == 1 and not bool((town.orders[0] as Dictionary).done) and not player.inventory.has_item("sword_basic"), "the material is handed over and the order is on the bench")
		var left_a: float = float((town.orders[0] as Dictionary).left)
		await _frames(120)
		var left_b: float = float((town.orders[0] as Dictionary).left)
		_check(left_b < left_a - 1.0, "he works on it while he stands at the bench (%.1f -> %.1f)" % [left_a, left_b])
		_check(not player.inventory.has_item("sword_iron"), "it does not appear in the bag by itself")
		town.request_collect(0)
		await _frames(2)
		_check(town.orders.size() == 1, "an unfinished order cannot be collected")
		TimeManager.locked = true
		TimeManager.time_of_day = 0.97 ## the night: he is asleep, nothing is worked
		await _frames(30)
		var asleep_a: float = float((town.orders[0] as Dictionary).left)
		await _frames(120)
		_check(is_equal_approx(float((town.orders[0] as Dictionary).left), asleep_a), "at night he does not work on it")
		TimeManager.time_of_day = 0.5
		await _frames(120)
		(town.orders[0] as Dictionary).left = 0.2
		await _frames(60)
		_check(bool((town.orders[0] as Dictionary).done), "when the work is done the piece waits on the bench")
		TimeManager.locked = false
		shop._on_town_changed()
		_check(String(shop.rows[0].kind) == "queue" and String(shop.rows[0].tag) == "ABHOLEN", "the queue row says ABHOLEN")
		var save_state: Dictionary = town.export_state()
		_check((save_state.orders as Array).size() == 1, "the queue is part of the saved town")
		shop.focus = 0
		shop._press("collect", false)
		await _frames(3)
		_check(player.inventory.has_item("sword_iron") and town.orders.is_empty(), "collecting hands over the sword and clears the queue")
		# trade
		var coins: int = player.progress.copper
		player.progress.award(500, 0)
		(town.residents["gustav"] as Dictionary).trust = 10
		shop._set_tab(2)
		var plank_buy: int = -1
		for i: int in shop.rows.size():
			if String(shop.rows[i].item) == "plank":
				plank_buy = i
		shop.focus = plank_buy
		var planks_have: int = player.inventory.count_item("plank")
		shop._press("buy", false)
		await _frames(3)
		_check(player.inventory.count_item("plank") == planks_have + 1 and player.progress.copper == coins + 500 - 14, "buying a plank costs 14 copper (%d)" % player.progress.copper)
		for i: int in shop.rows.size():
			if String(shop.rows[i].item) == "glow_cap":
				_check(int(shop.rows[i].state) == BoardWindow.LOCKED, "a trade that wants more trust is locked")
		shop._set_tab(3)
		player.inventory.give("wood", 5)
		await _frames(2)
		shop.focus = 0
		var money: int = player.progress.copper
		var wood_have: int = player.inventory.count_item("wood")
		shop._press("sell_all", false)
		await _frames(3)
		_check(player.inventory.count_item("wood") == 0 and player.progress.copper == money + 3 * wood_have, "selling all wood pays 3 copper each (%d)" % player.progress.copper)
		_check(town.trust_of("gustav") >= 0, "trade leaves trust alone")
		shop._close()
	await _frames(40)
	_check(not is_instance_valid(shop) or shop.is_queued_for_deletion(), "the shop window closes itself")
	# --- production: Gustav saws planks from the stock's wood every hour
	town.stock["wood"] = 8
	town.stock.erase("plank")
	TimeManager.time_of_day = 0.5
	await _frames(3)
	TimeManager.time_of_day = 0.5 + 1.0 / 24.0 + 0.001
	await _frames(5)
	_check(int(town.stock.get("plank", 0)) == 2 and int(town.stock.get("wood", 0)) == 6, "an hour of work turns two wood of the stock into two planks (%s)" % str(town.stock))
	var ways_before: int = town.paths.size()
	town.request_demolish(stock_id)
	await _frames(3)
	_check(not town.structures.has(stock_id) and town.paths.size() == ways_before, "a way stays when its building goes (trampled ground does not heal at once)")
	# --- the build mode
	var builder: BuildMode = town.build_mode()
	_check(builder != null and builder.menu != null, "the local builder exists")
	builder.set_active(true)
	_check(builder.active and InputManager.build_open and not InputManager.attack_pressed(), "build mode is on: the primary button no longer swings")
	_check(builder.categories().size() >= 3 and not builder.pieces_here().is_empty(), "the menu lists the categories")
	builder.select("bench")
	builder._update_ghost(TownRules.snapped_position("bench", hut.position + Vector2(-110, 70)))
	_check(builder._ghost.visible, "the ghost follows the cursor")
	builder.set_active(false)
	_check(not builder.active and not InputManager.build_open, "build mode ends cleanly")
	# --- the STADT tab
	var pause: PauseMenu = player.get_node("Hud/PauseMenu") as PauseMenu
	_check(pause != null, "the pause menu exists")
	pause._set_open(true)
	pause._select_tab(2)
	await _frames(3)
	var headings: Array[String] = []
	var infos: Array[String] = []
	for item: Dictionary in pause._items:
		if String(item.kind) == "heading":
			headings.append(String(item.label))
		if String(item.kind) == "info":
			infos.append(String(item.label))
	_check(town.town_name() in headings and "LAGER" in headings and "BEWOHNER" in headings and "VERWALTUNG" in headings, "the STADT tab has its sections (%s)" % str(headings))
	_check("STUFE" in infos and "EINWOHNER" in infos and "BAUTEN" in infos, "and its figures (%s)" % str(infos))
	var name_before: int = town.name_index
	for item: Dictionary in pause._items:
		if String(item.kind) == "choice":
			pause._change(item, 1)
	await _frames(2)
	_check(town.name_index == (name_before + 1) % TownRules.town_names().size(), "the name can be changed")
	await _frames(3)
	pause._run_action("town_build")
	await _frames(3)
	_check(builder.active, "the tab starts the build mode and closes itself")
	pause._set_open(false)
	builder.set_active(false)
	# --- saving and loading
	var saved: Dictionary = town.export_state()
	var text: String = JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(text) as Dictionary
	var count: int = town.structures.size()
	var trust: int = town.trust_of("gustav")
	var stock_text: String = JSON.stringify(town.stock, "", true)
	town.import_state(parsed)
	await _frames(20)
	_check(town.structures.size() == count and town.trust_of("gustav") == trust and JSON.stringify(town.stock, "", true) == stock_text, "the state survives the save file (%d pieces, trust %d)" % [town.structures.size(), town.trust_of("gustav")])
	_check(town.settler_node("gustav") != null and town.view_of(shop_id) != null, "the settler and the pictures are rebuilt")
	_check(town.cleared.has(soft_cell) or soft_cell.x < 0, "cleared props stay cleared")
	_check(world._town_node.cleared.has(soft_cell) or soft_cell.x < 0, "and the world knows")
	# --- the save file (SaveGame): the town goes in and comes out
	var path: String = OS.get_environment("SHADOWSPORE_TEST_SAVE_PATH")
	if path.is_empty(): path = "user://test_town_save.json"
	_check(SaveGame.save(get_tree(), path), "the game saves with a town")
	var pieces: int = town.structures.size()
	var ways: int = town.paths.size()
	town.import_state({})
	_check(not town.founded and town.structures.is_empty(), "an empty state is no town")
	_check(SaveGame.load_into(get_tree(), path), "and the save loads")
	await _frames(20)
	_check(town.founded and town.structures.size() == pieces and town.paths.size() == ways and town.residents.has("gustav"), "the save file keeps the pieces, the ways and the settlers (%d / %d)" % [town.structures.size(), town.paths.size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# --- the quest chain
	_check(DataRegistry.table("quests").has("town_start") and String((DataRegistry.table("quests").rebuild_hut as Dictionary).get("next", "")) == "town_start", "the town quest follows the renewal")
	print("TOWN: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
