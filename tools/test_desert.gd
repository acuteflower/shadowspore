extends Node
## Sonnenquarz-Öde stages 1+2 (docs/quarzwueste_konzept.md): northern desert biome & super region 6, 96-tile arid transition,
## sand/steppe/quartz surfaces, sandstone-quartz mesa relief, 9 desert flora species & 7 items, zero fallen logs, and world map entry.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass

const DESERT_ITEMS: Array[String] = ["sun_fig", "crown_fig", "cactus_wood", "cactus_pulp", "quartz_aloe", "night_cactus_bloom", "sand_tuber", "palm_wood", "sun_date", "oasis_blossom", "sun_quartz"]

var _checks: int = 0
var _failures: int = 0
const HUT: Vector2i = Vector2i(786, 676)
const HEX_CENTRE: Vector2i = Vector2i(821, 892)
const DESERT_DEEP: Vector2i = Vector2i(842, 175)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("DESERT: " + message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var data: Dictionary = DataRegistry.table("world_map")
	var map: RegionMap = RegionMap.new(0, data)
	_check(map.supers.size() == 7 and map.regions.size() == 35, "seven areas, 35 regions")
	_check(map.own_biomes.has("quartz_desert") and map.own_biomes.has("witch_forest"), "own_biomes has witch_forest and quartz_desert")
	_check(map.area_name(6) == "Sonnenquarz-Öde" and map.super_at(DESERT_DEEP) == 6 and map.biome_at(DESERT_DEEP) == "quartz_desert", "super 6 is Sonnenquarz-Öde")
	_check(map.biome_at(HUT) == "meadow" and map.biome_at(HEX_CENTRE) == "witch_forest", "town and Hexenwald keep their biomes")

	# Arid blend field vs gloom blend field (strictly independent!)
	BiomeBlend.install(map)
	_check(BiomeBlend.arid_at(Vector2(HUT) * 16.0) == 0.0 and BiomeBlend.arid_at(Vector2(HEX_CENTRE) * 16.0) == 0.0, "arid_at is 0 in town and Hexenwald")
	_check(BiomeBlend.amount_at(Vector2(DESERT_DEEP) * 16.0) == 0.0 and BiomeBlend.arid_at(Vector2(DESERT_DEEP) * 16.0) > 0.99, "deep desert has full arid_at and zero gloom")

	# Smooth 96-tile transition walking north across the southern desert border around x = 900
	var start_a: float = BiomeBlend.arid_at(Vector2(900, 420) * 16.0)
	var mid_seen: bool = false
	var step_ok: bool = true
	var prev_a: float = start_a
	for y: int in range(416, 220, -4):
		var a: float = BiomeBlend.arid_at(Vector2(900, y) * 16.0)
		step_ok = step_ok and absf(a - prev_a) < 0.16
		if a > 0.20 and a < 0.80:
			mid_seen = true
		prev_a = a
	_check(start_a == 0.0 and mid_seen and prev_a > 0.98 and step_ok, "walking north rises smoothly across the 96-tile arid transition (0 -> %.2f)" % prev_a)

	# Relief style 6 & glow flag
	var relief: Relief = Relief.new()
	_check(relief._at(DESERT_DEEP.x, DESERT_DEEP.y, 3) == 206 and relief.style(DESERT_DEEP.x, DESERT_DEEP.y) == 6, "desert relief uses biome 206 and sandstone-quartz style 6")
	_check(relief.has_glow_style(Rect2i(DESERT_DEEP - Vector2i(8, 8), Vector2i(16, 16))), "desert style 6 enables quartz-vein glow pass")

	# Data tables: all 9 desert flora sheets & 7 items load cleanly; fallen_desert_log is absent
	var plants: Dictionary = DataRegistry.table("plants")
	var items: Dictionary = DataRegistry.table("items")
	var harvest: Dictionary = DataRegistry.table("harvest")
	_check(not harvest.has("fallen_desert_log"), "harvest table has no fallen_desert_log")
	for kind: String in PropGenerator.DESERT_KINDS:
		var spec: Dictionary = plants.get(kind, {}) as Dictionary
		var tex: Texture2D = load(String(spec.get("texture", ""))) as Texture2D
		var glow_ok: bool = true
		if spec.has("glow"):
			var gtex: Texture2D = load(String(spec.glow)) as Texture2D
			glow_ok = gtex != null and tex != null and gtex.get_size() == tex.get_size()
		var growth_ok: bool = not spec.has("growth") or load(String(spec.growth)) != null
		var stripped_ok: bool = not spec.has("stripped") or load(String(spec.stripped)) != null
		_check(not spec.is_empty() and tex != null and glow_ok and growth_ok and stripped_ok, "desert flora %s sheets load cleanly" % kind)
	for item_id: String in DESERT_ITEMS:
		var item_spec: Dictionary = items.get(item_id, {}) as Dictionary
		_check(not item_spec.is_empty() and load(String(item_spec.get("icon", ""))) is Texture2D, "desert item %s icon loads" % item_id)

	# World level: shared ground layer, sparse 9-species desert flora, zero foreign props/clover/logs
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	world.set_process(false)
	world.get_node("Wildlife").process_mode = Node.PROCESS_MODE_DISABLED
	for loaded: Vector2i in world._chunks.keys():
		world._unload_chunk(loaded)
	_check(world._layers["quartz_desert"] == world._ground, "quartz_desert uses the shared ground layer")

	var desert_props: int = 0
	var desert_logs: int = 0
	var foreign_props: int = 0
	var seen_kinds: Dictionary = {}
	var prop_chunk: Vector2i = Vector2i(26, 5)
	for cy: int in range(3, 8):
		for cx: int in range(21, 31):
			var rect: Rect2i = Rect2i(Vector2i(cx, cy) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			var chunk_count: int = 0
			for entry: Dictionary in world._generator.props_for_chunk(rect):
				var cell: Vector2i = entry.cell as Vector2i
				if not world._generator.is_desert_bare(cell):
					continue
				var k: String = String(entry.kind)
				var arid_here: float = BiomeBlend.arid_at(Vector2(cell) * 16.0 + Vector2(8.0, 8.0))
				if PropGenerator.DESERT_KINDS.has(k):
					desert_props += 1
					chunk_count += 1
					seen_kinds[k] = int(seen_kinds.get(k, 0)) + 1
				elif arid_here >= 0.35 or (k != "bush" and k != "grass"):
					foreign_props += 1
			if chunk_count >= 3 and cx >= 23 and cx <= 29 and cy >= 4 and cy <= 7:
				prop_chunk = Vector2i(cx, cy)
			for idx: int in 16:
				var spec: Dictionary = FallenLogScatter.candidate(world, Vector2i(cx, cy), idx, [] as Array[Dictionary])
				if not spec.is_empty() and world._generator.is_desert_bare(Vector2i((spec.pos as Vector2) / 16.0)):
					desert_logs += 1
	_check(desert_logs == 0, "quartz_desert spawns strictly zero fallen logs (%d)" % desert_logs)
	_check(foreign_props == 0, "quartz_desert has zero foreign props, beds, or deep meadow flora (%d)" % foreign_props)
	_check(seen_kinds.size() == PropGenerator.DESERT_KINDS.size(), "all %d desert flora species generate in Sonnenquarz-Öde (saw %d: %s)" % [PropGenerator.DESERT_KINDS.size(), seen_kinds.size(), str(seen_kinds)])
	_check(desert_props >= 220 and desert_props <= 3200, "desert flora stays balanced around oases and open dunes (%d props across 50 chunks)" % desert_props)

	# Verify all 4 desert oases integrate with WorldRivers, Terrain, and BiomeBlend.oasis_at
	var oasis_points: Dictionary = {
		"oasis_west": Vector2i(508, 95),
		"oasis_lagoon": Vector2i(708, 139),
		"oasis_twins": Vector2i(798, 209),
		"oasis_spring": Vector2i(1002, 119),
	}
	for o_id: String in oasis_points.keys():
		var o_tile: Vector2i = oasis_points[o_id] as Vector2i
		var o_px: Vector2 = Vector2(o_tile) * 16.0 + Vector2(8.0, 8.0)
		var o_chunk: Vector2i = Vector2i(floori(o_px.x / float(WorldLevel.CHUNK * 16)), floori(o_px.y / float(WorldLevel.CHUNK * 16)))
		world._load_chunk(o_chunk)
		for _frame: int in 4:
			await get_tree().process_frame
		var in_water: bool = world._rivers.lake_at(o_px)
		var surf_w: String = Terrain.surface_at(o_px)
		var bank_px: Vector2 = o_px + Vector2(360.0, 0.0)
		var bank_oasis: float = BiomeBlend.oasis_at(bank_px)
		var best_oasis: float = bank_oasis
		for ang_i: int in 8:
			var ang: float = float(ang_i) * TAU / 8.0
			for rad: float in [120.0, 180.0, 240.0, 320.0, 380.0]:
				var probe: Vector2 = o_px + Vector2.from_angle(ang) * rad
				if not world._rivers.lake_at(probe):
					best_oasis = maxf(best_oasis, BiomeBlend.oasis_at(probe))
		_check(in_water and (surf_w == "shallow_water" or surf_w == "deep_water") and best_oasis > 0.5, "desert oasis %s integrates water + lush shore blend (lake=%s, surf=%s, oasis=%.2f)" % [o_id, str(in_water), surf_w, best_oasis])
		# Verify oasis RiverDetails uses oasis-native water & bank sheets with 0 jellies & 0 temperate river flora
		var details_nodes: Array[RiverDetails] = []
		_collect_river_details(world, details_nodes)
		_check(details_nodes.size() > 0, "oasis %s attaches RiverDetails" % o_id)
		var oasis_bank_n: int = 0
		var oasis_water_n: int = 0
		var temp_flora_n: int = 0
		var total_jellies: int = 0
		for rd: RiverDetails in details_nodes:
			total_jellies += rd._jellies.size()
			for child: Node in rd.get_children():
				var sp: Sprite2D = child as Sprite2D
				if sp == null or sp.texture == null:
					continue
				var tpath: String = sp.texture.resource_path
				if tpath.ends_with("oasis_bank_details.png"):
					oasis_bank_n += 1
				elif tpath.ends_with("oasis_water_flora.png"):
					oasis_water_n += 1
				elif tpath.ends_with("river_details.png") or tpath.ends_with("bank_details.png") or tpath.ends_with("water_flora.png"):
					temp_flora_n += 1
		_check(total_jellies == 0, "oasis %s has 0 glowing jellies (found=%d)" % [o_id, total_jellies])
		_check(temp_flora_n == 0, "oasis %s has 0 temperate river/bank sprites (found=%d)" % [o_id, temp_flora_n])
		_check(oasis_bank_n > 0 and oasis_water_n > 0, "oasis %s populates oasis bank & water flora (bank=%d, water=%d)" % [o_id, oasis_bank_n, oasis_water_n])
		world._unload_chunk(o_chunk)

	world._load_chunk(prop_chunk)
	for _frame: int in 8:
		await get_tree().process_frame
	_check(world._chunks.has(prop_chunk), "deep desert chunk %s loads" % str(prop_chunk))
	if world._chunks.has(prop_chunk):
		var ch: Variant = world._chunks[prop_chunk]
		_check(ch.cells.has("quartz_desert") and ch.clover.is_empty() and ch.fallen_logs.is_empty() and not ch.things.is_empty(), "deep desert chunk has ground tiles, zero clover, zero fallen logs, and desert props")
	world._unload_chunk(prop_chunk)

	# Interactive flora behavior checks: night_cactus day/night toggle, prickly_pear & crown_cactus pick, sand_tuber pull
	world.opening_over = true
	var nc: Flora = (load(String(plants.night_cactus.scene)) as PackedScene).instantiate() as Flora
	nc.setup(world, Vector2i(840, 175), "night_cactus", 1)
	add_child(nc)
	TimeManager.time_of_day = 0.5
	nc._row = -1
	nc._pose()
	var closed_day: bool = nc._closed and nc.prompt() == ""
	TimeManager.time_of_day = 0.0
	nc._row = -1
	nc._pose()
	var open_night: bool = not nc._closed and nc.prompt() == "PFLÜCKEN"
	_check(closed_day and open_night, "night_cactus closes by day and opens to bloom at night")
	nc.queue_free()

	var pear: Bush = (load(String(plants.prickly_pear.scene)) as PackedScene).instantiate() as Bush
	pear.setup(world, Vector2i(841, 175), "prickly_pear", 1)
	add_child(pear)
	var pear_prompt_before: String = pear.prompt()
	pear.apply_state({"p": 1, "k": "prickly_pear"}, "pick")
	_check(pear_prompt_before == "PFLÜCKEN" and bool(pear.state.get("p", 0)) and pear.prompt() == "", "prickly_pear can be picked cleanly")
	pear.queue_free()

	var crown: FirTree = (load(String(plants.crown_cactus.scene)) as PackedScene).instantiate() as FirTree
	crown.setup(world, Vector2i(842, 175), "crown_cactus", 2)
	add_child(crown)
	var crown_prompt_before: String = crown.prompt()
	crown.apply_state({"p": 1, "k": "crown_cactus"}, "pick")
	_check(crown_prompt_before == "PFLÜCKEN" and bool(crown.state.get("p", 0)) and crown.prompt() == "", "crown_cactus can be picked cleanly")
	crown.queue_free()

	var tuber: Flora = (load(String(plants.sand_tuber.scene)) as PackedScene).instantiate() as Flora
	tuber.setup(world, Vector2i(843, 175), "sand_tuber", 0)
	add_child(tuber)
	var tuber_ok: bool = tuber.prompt() == "AUSZIEHEN" and tuber._spec.has("soil_burst")
	tuber.apply_state({"p": 3, "k": "sand_tuber"}, "pick")
	_check(tuber_ok and tuber.prompt() == "", "sand_tuber pulls cleanly with sand burst")
	tuber.queue_free()

	var palm: FirTree = (load(String(plants.sun_palm.scene)) as PackedScene).instantiate() as FirTree
	palm.setup(world, Vector2i(712, 156), "sun_palm", 2)
	add_child(palm)
	var palm_prompt_before: String = palm.prompt()
	palm.apply_state({"p": 1, "k": "sun_palm"}, "pick")
	var palm_after_pick: bool = palm_prompt_before == "PFLÜCKEN" and bool(palm.state.get("p", 0)) and palm.prompt() == ""
	palm.apply_state({"f": 1, "h": palm.slots(), "k": "sun_palm"}, "")
	await get_tree().process_frame
	_check(palm_prompt_before == "PFLÜCKEN" and palm_after_pick and palm.is_depleted() and palm._body_shape.disabled and not palm._crown.visible, "sun_palm picks dates and chops cleanly")
	palm.queue_free()

	var lily: Flora = (load(String(plants.oasis_lily.scene)) as PackedScene).instantiate() as Flora
	lily.setup(world, Vector2i(713, 156), "oasis_lily", 1)
	add_child(lily)
	var lily_before: String = lily.prompt()
	lily.apply_state({"p": 1, "k": "oasis_lily"}, "pick")
	_check(lily_before == "PFLÜCKEN" and bool(lily.state.get("p", 0)) and lily.prompt() == "", "oasis_lily picks blossom cleanly")
	lily.queue_free()

	var qrock: Rock = (load(String(plants.sun_quartz_rock.scene)) as PackedScene).instantiate() as Rock
	qrock.setup(world, Vector2i(844, 175), "sun_quartz_rock", 2)
	add_child(qrock)
	var solid_full: bool = not qrock._body_shape.disabled and not qrock.is_depleted()
	qrock.apply_state({"h": qrock.slots(), "k": "sun_quartz_rock"}, "strip")
	await get_tree().process_frame
	_check(solid_full and qrock.is_depleted() and qrock._body_shape.disabled, "sun_quartz_rock mines to rubble and disables collision")
	qrock.queue_free()

	# Sample across broad expanded desert (X=560..980, Y=90..230) to verify sand dominates (~93-96%) while sparse natural white quartz outcrops (~3-9%) register cleanly
	var sand_count: int = 0
	var quartz_count: int = 0
	for ty: int in range(96, 232, 6):
		for tx: int in range(560, 980, 6):
			if relief.is_land(tx, ty) and relief._at(tx, ty, 3) == 206 and relief.kind(tx, ty) == Relief.FLOOR:
				var surf: String = Terrain.surface_at(Vector2(tx, ty) * 16.0 + Vector2(8, 8))
				if surf == "sand": sand_count += 1
				elif surf == "quartz": quartz_count += 1
	var total_surf: int = sand_count + quartz_count
	var q_ratio: float = float(quartz_count) / float(maxi(total_surf, 1))
	_check(sand_count > 600 and quartz_count >= 12 and q_ratio < 0.14, "Terrain.surface_at keeps open sand dominant (%d) with sparse natural quartz outcrops (%d, %.1f%%)" % [sand_count, quartz_count, q_ratio * 100.0])

	# World map shader uniforms
	var window: MapWindow = MapWindow.new()
	add_child(window)
	window._load_data()
	_check(window._area_names.has("Sonnenquarz-Öde") and (window._material.get_shader_parameter("area_biomes") as PackedInt32Array)[6] == 6, "world map registers Sonnenquarz-Öde with palette 6")
	window.queue_free()

	# WorldWind desert sand drift stays scalar horizontal (y == 0) with bounded speed
	var wind: WorldWind = world.get_node_or_null("WorldWind") as WorldWind
	_check(wind != null, "WorldLevel attaches WorldWind")
	if wind != null:
		var start_x: float = wind.sand_drift.x
		wind._process(0.1)
		var dx: float = wind.sand_drift.x - start_x
		_check(wind.sand_drift.y == 0.0 and dx > 0.0 and dx < 5.0, "WorldWind desert sand drift stays calm and never climbs vertically (dx=%.2f, y=%.2f)" % [dx, wind.sand_drift.y])

	# Desert & oasis wildlife removal check across Day (0.5) and Night (0.97)
	var sample_chunks: Array[Vector2i] = [Vector2i(16, 2), Vector2i(21, 3), Vector2i(14, 4), Vector2i(20, 5)]
	for phase_label: String in ["day", "night"]:
		TimeManager.set_time(0.5 if phase_label == "day" else 0.97)
		for sc: Vector2i in sample_chunks:
			world._load_chunk(sc)
		for _f: int in 6:
			await get_tree().process_frame
		var found_animals: Array[String] = []
		_collect_desert_animals(world, found_animals)
		_check(found_animals.is_empty(), "desert & oases have 0 animals at %s (found=%s)" % [phase_label, str(found_animals)])
		for sc: Vector2i in sample_chunks:
			world._unload_chunk(sc)
		await get_tree().process_frame

	world.queue_free()
	await get_tree().process_frame
	print("DESERT: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _collect_river_details(root: Node, out: Array[RiverDetails]) -> void:
	if root is RiverDetails:
		out.append(root as RiverDetails)
	for child: Node in root.get_children():
		_collect_river_details(child, out)


func _collect_desert_animals(root: Node, out: Array[String]) -> void:
	if root is RiverAnimal or root is WildRabbit or root is WildCorvid or root is WildMeadowBird or root is WoodlandMammal or root is WildBear or root is MeadowButterfly or root is TinyWildlife or root is LeafCritter:
		var pos: Vector2 = (root as Node2D).global_position
		if BiomeBlend.arid_at(pos) >= 0.25:
			out.append("%s@(%d,%d)" % [root.get_class(), int(pos.x), int(pos.y)])
	for child: Node in root.get_children():
		_collect_desert_animals(child, out)
