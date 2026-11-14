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
	var quartz_rocks_off_quartz: int = 0
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
					if k == "sun_quartz_rock":
						var qpos: Vector2 = entry.pos as Vector2
						var qvar: int = int(entry.variant)
						if not world._generator._quartz_rock_fits(qpos, qvar) or Terrain.surface_at(qpos) != "quartz":
							quartz_rocks_off_quartz += 1
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
	_check(quartz_rocks_off_quartz == 0 and int(seen_kinds.get("sun_quartz_rock", 0)) >= 6, "every sun_quartz_rock emerges exclusively from ground quartz outcrops (off_quartz=%d, count=%d)" % [quartz_rocks_off_quartz, int(seen_kinds.get("sun_quartz_rock", 0))])
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
		var bad_water_z: int = 0
		var bad_water_shore: int = 0
		for rd: RiverDetails in details_nodes:
			total_jellies += rd._jellies.size()
			for idx_s: int in rd._sprites.size():
				var w_sp: Sprite2D = rd._sprites[idx_s]
				var w_row: int = rd._rows[idx_s]
				if w_row in [20, 21] and w_sp.z_index != -5:
					bad_water_z += 1
				elif w_row == 22 and w_sp.z_index != -6:
					bad_water_z += 1
				if w_row >= 20 and world._rivers.field_at(w_sp.position).x > -4.5:
					bad_water_shore += 1
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
		_check(bad_water_z == 0 and bad_water_shore == 0, "oasis %s water flora separates floating (-5) above submerged (-6) and stays off shore (bad_z=%d, bad_shore=%d)" % [o_id, bad_water_z, bad_water_shore])
		world._unload_chunk(o_chunk)

	# Verify oasis_water_flora.png 2-frame pairs stay coherent (no color/shape swap between rows 0/1, 2/3, 4/5)
	var ow_img: Image = (load("res://assets/water/oasis_water_flora.png") as Texture2D).get_image()
	var ow_pairs_ok: bool = true
	for pair_idx: int in [0, 1, 2]:
		var r0: int = pair_idx * 2
		var r1: int = r0 + 1
		for v: int in 6:
			var sum0: Vector3 = Vector3.ZERO
			var sum1: Vector3 = Vector3.ZERO
			var cnt0: int = 0
			var cnt1: int = 0
			for py: int in 32:
				for px: int in 32:
					var c0: Color = ow_img.get_pixel(v * 32 + px, r0 * 32 + py)
					var c1: Color = ow_img.get_pixel(v * 32 + px, r1 * 32 + py)
					if c0.a > 0.1:
						sum0 += Vector3(c0.r, c0.g, c0.b)
						cnt0 += 1
					if c1.a > 0.1:
						sum1 += Vector3(c1.r, c1.g, c1.b)
						cnt1 += 1
			if cnt0 == 0 or cnt1 == 0:
				ow_pairs_ok = false
			else:
				var mean0: Vector3 = sum0 / float(cnt0)
				var mean1: Vector3 = sum1 / float(cnt1)
				if mean0.distance_to(mean1) > 0.10 or absf(float(cnt0 - cnt1)) > float(maxi(cnt0, cnt1)) * 0.25:
					ow_pairs_ok = false
	_check(ow_pairs_ok, "oasis_water_flora.png row pairs (0/1, 2/3, 4/5) preserve plant color and silhouette across frames")

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
	var palm_frame_before: int = palm._crown.frame
	var palm_glow_before: int = palm._crown_glow.frame
	palm.apply_state({"p": 1, "k": "sun_palm"}, "pick")
	var palm_frame_after: int = palm._crown.frame
	var palm_glow_after: int = palm._crown_glow.frame
	var palm_after_pick: bool = palm_prompt_before == "PFLÜCKEN" and bool(palm.state.get("p", 0)) and palm.prompt() == "" and palm_frame_before != palm_frame_after and palm_glow_before != palm_glow_after
	palm.apply_state({"f": 1, "h": palm.slots(), "k": "sun_palm"}, "")
	await get_tree().process_frame
	_check(palm_prompt_before == "PFLÜCKEN" and palm_after_pick and palm.is_depleted() and palm._body_shape.disabled and not palm._crown.visible, "sun_palm switches crown & glow frames on date pick and chops cleanly")
	palm.queue_free()

	# Verify sun_palm.png visibly removes dates between Row 1 (unpicked) and Row 4 (picked) across all 6 variants
	var palm_img: Image = (load("res://assets/props/sun_palm.png") as Texture2D).get_image()
	var palm_visual_diff_ok: bool = true
	var min_palm_diff: int = 999999
	for pv: int in 6:
		var diff_px: int = 0
		for py: int in 200:
			for px: int in 112:
				var cu: Color = palm_img.get_pixel(pv * 112 + px, 200 + py)
				var cp: Color = palm_img.get_pixel(pv * 112 + px, 800 + py)
				if not cu.is_equal_approx(cp):
					diff_px += 1
		min_palm_diff = mini(min_palm_diff, diff_px)
		if diff_px < 24:
			palm_visual_diff_ok = false
	_check(palm_visual_diff_ok, "sun_palm.png visibly changes crown pixels when dates are harvested on all 6 variants (min_diff=%d px)" % min_palm_diff)

	# Verify rain, storm, fog, ground wetness, and rain exposure are completely disabled in quartz_desert
	var wm: WeatherManager = WeatherManager.current
	_check(wm != null, "WeatherManager.current exists on WorldLevel")
	if wm != null:
		for _wf: int in 12:
			if wm.field.ready_now:
				break
			await get_tree().process_frame
		wm.force("storm", 0.0)
		var desert_focus: Vector2 = Vector2(840, 175) * 16.0
		var oasis_focus: Vector2 = Vector2(712, 156) * 16.0
		wm.focus = desert_focus
		var cam_prev: Camera2D = get_viewport().get_camera_2d()
		var test_cam: Camera2D = Camera2D.new()
		test_cam.position = desert_focus
		add_child(test_cam)
		test_cam.make_current()
		for _step: int in 6:
			wm.follow(false, 4.0)
		var rainless_desert: bool = wm.rain <= 0.001 and wm.local_rain <= 0.001 and wm.storm <= 0.001 and wm.fog <= 0.001 and wm.ground_wet <= 0.001 and wm.puddle <= 0.001
		var rainless_points: bool = wm.rain_at(desert_focus) == 0.0 and wm.exposure_at(desert_focus) == 0.0 and wm.rain_at(oasis_focus) == 0.0
		var dry_label: bool = not (wm.display_name() in ["NIESELREGEN", "REGEN", "STARKREGEN", "GEWITTER", "NEBEL"])
		_check(rainless_desert and rainless_points and dry_label, "desert disables rain, storm, fog & wetness completely even during forced storm (name=%s, rain=%.3f, wet=%.3f)" % [wm.display_name(), wm.rain, wm.ground_wet])
		wm.release()
		if cam_prev != null:
			cam_prev.make_current()
		test_cam.queue_free()

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

	# Desert & oasis native wildlife verification (6 species, 0 temperate/forest leaks, day/night rhythm & interactions)
	var wildlife_table: Dictionary = DataRegistry.table("wildlife")
	var desert_species: Array[String] = ["oryx", "fennec", "jerboa", "agama", "desert_falcon", "scarab"]
	for sp: String in desert_species:
		_check(wildlife_table.has(sp), "data/wildlife.json defines desert species %s" % sp)
		var entry_sp: Dictionary = wildlife_table[sp] as Dictionary
		var biomes_sp: Array = entry_sp.get("biomes", []) as Array
		_check(biomes_sp.has("quartz_desert"), "%s restricts habitat to quartz_desert" % sp)
		if entry_sp.has("sprite"):
			var tex_sp: Texture2D = load(String(entry_sp["sprite"])) as Texture2D
			var exp_cols: int = int(entry_sp.get("hframes", 52))
			var exp_rows: int = int(entry_sp.get("vframes", 32))
			_check(tex_sp != null and tex_sp.get_width() == exp_cols * 64 and tex_sp.get_height() == exp_rows * 64, "%s sprite sheet loads cleanly (%dx%d cells)" % [sp, exp_cols, exp_rows])
	var burrow_tex: Texture2D = load("res://assets/wildlife/desert_burrow.png") as Texture2D
	_check(burrow_tex != null and burrow_tex.get_width() == 40 and burrow_tex.get_height() == 24, "desert_burrow.png loads at 40x24")

	# Stream a 16-chunk desert & oasis slice at daytime (0.46) and verify natural spawning + zero foreign wildlife
	world.get_node("Wildlife").process_mode = Node.PROCESS_MODE_INHERIT
	TimeManager.set_time(0.46)
	var sample_chunks: Array[Vector2i] = []
	for cy_w: int in range(3, 7):
		for cx_w: int in range(21, 25):
			sample_chunks.append(Vector2i(cx_w, cy_w))
	sample_chunks.append(Vector2i(16, 2))
	sample_chunks.append(Vector2i(14, 4))
	for sc: Vector2i in sample_chunks:
		world._load_chunk(sc)
	world._finish_commit()
	for _f: int in sample_chunks.size() + 16:
		await get_tree().physics_frame

	var foreign_animals: Array[String] = []
	var seen_desert_sp: Dictionary = {}
	_inspect_desert_wildlife(world, desert_species, seen_desert_sp, foreign_animals)
	_count_unlit_desert_wildlife(world, desert_species)
	_check(foreign_animals.is_empty(), "zero non-desert animals spawn in quartz_desert & oases (foreign=%s)" % str(foreign_animals))
	_check(seen_desert_sp.size() >= 4, "streamed desert chunks naturally populate native desert species by day (saw=%s)" % str(seen_desert_sp))

	# Switch to deep night (0.0) and verify scarabs despawn while nocturnal fennecs/jerboas wake and agamas hide
	TimeManager.set_time(0.0)
	for _fn: int in sample_chunks.size() + 14:
		await get_tree().physics_frame
	var foreign_night: Array[String] = []
	var seen_night_sp: Dictionary = {}
	_inspect_desert_wildlife(world, desert_species, seen_night_sp, foreign_night)
	_check(foreign_night.is_empty() and int(seen_night_sp.get("scarab", 0)) == 0, "night desert has 0 foreign animals and 0 active diurnal scarabs (foreign=%s, night=%s)" % [str(foreign_night), str(seen_night_sp)])

	# Behavioral & ecological unit checks on an open desert tile
	var test_pos: Vector2 = Vector2(DESERT_DEEP) * 16.0
	var test_chunk: Vector2i = Vector2i(floori(test_pos.x / 512.0), floori(test_pos.y / 512.0))
	world._load_chunk(test_chunk)
	world._finish_commit()
	for _ft: int in 4:
		await get_tree().physics_frame
	for probe_i: int in 64:
		var cand_tp: Vector2 = Vector2(test_chunk) * 512.0 + Vector2(96.0 + float((probe_i % 8) * 44), 96.0 + float((probe_i / 8) * 44))
		if world._fauna_habitat(cand_tp, "jerboa") and world._fauna_habitat(cand_tp + Vector2(28.0, 0.0), "jerboa") and world._fauna_habitat(cand_tp + Vector2(-28.0, 0.0), "jerboa"):
			test_pos = cand_tp
			break

	TimeManager.set_time(0.5)
	var woodland_pop: WoodlandPopulation = world.get_node("Wildlife/Woodland") as WoodlandPopulation
	var mammal_scene: PackedScene = load("res://src/entities/wildlife/woodland_mammal.tscn") as PackedScene

	var oryx_bull: WoodlandMammal = mammal_scene.instantiate() as WoodlandMammal
	oryx_bull.name = "TestOryxBull"
	oryx_bull.species = "oryx"
	oryx_bull.appearance = 0
	oryx_bull.position = test_pos
	oryx_bull.home = test_pos
	woodland_pop._residents.add_child(oryx_bull)

	var oryx_calf: WoodlandMammal = mammal_scene.instantiate() as WoodlandMammal
	oryx_calf.name = "TestOryxCalf"
	oryx_calf.species = "oryx"
	oryx_calf.appearance = 3
	oryx_calf.position = test_pos + Vector2(18.0, 6.0)
	oryx_calf.home = test_pos
	woodland_pop._residents.add_child(oryx_calf)
	var oryx_mat: Material = (oryx_bull.get_node("Sprite2D") as Sprite2D).material
	var oryx_unlit: bool = oryx_mat == Unlit.material() or (oryx_mat is CanvasItemMaterial and (oryx_mat as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED)
	_check(oryx_calf.is_calf() and oryx_calf.is_young() and not oryx_bull.is_young(), "oryx build 3 is recognized as calf/young while bull build 0 is adult")
	_check(not oryx_unlit, "oryx sprite has zero Unlit night-glow material")

	var agama_a: WoodlandMammal = mammal_scene.instantiate() as WoodlandMammal
	agama_a.name = "TestAgamaA"
	agama_a.species = "agama"
	agama_a.appearance = 0
	agama_a.position = test_pos + Vector2(54.0, -16.0)
	agama_a.home = agama_a.position
	woodland_pop._residents.add_child(agama_a)

	var agama_b: WoodlandMammal = mammal_scene.instantiate() as WoodlandMammal
	agama_b.name = "TestAgamaB"
	agama_b.species = "agama"
	agama_b.appearance = 2
	agama_b.position = test_pos + Vector2(76.0, -14.0)
	agama_b.home = agama_b.position
	woodland_pop._residents.add_child(agama_b)

	await get_tree().physics_frame
	agama_a.hear_raptor_overhead(agama_a.global_position + Vector2(10.0, -8.0))
	_check(agama_a.mood == WoodlandMammal.Mood.SLEEP, "agama flattens in camouflage freeze (SLEEP) when desert_falcon shadow passes overhead")
	agama_a._issue(WoodlandMammal.Mood.REST, 1.0)
	agama_b._issue(WoodlandMammal.Mood.REST, 1.0)

	var events: WildlifeEvents = world.get_node("WildlifeEvents") as WildlifeEvents
	var duel_ok: bool = events.begin_event("agama_duel", agama_a, agama_b)
	_check(duel_ok and agama_a.mood == WoodlandMammal.Mood.BARK and agama_b.mood == WoodlandMammal.Mood.ALERT, "WildlifeEvents starts push-up agama_duel (challenger BARK, rival ALERT)")
	events.finish_event("test_done")

	TimeManager.set_time(0.0)
	_check(agama_a._rest_hours(), "agama enters rest/hidden hours at night")
	var fennec_hunter: WoodlandMammal = mammal_scene.instantiate() as WoodlandMammal
	fennec_hunter.name = "TestFennecHunter"
	fennec_hunter.species = "fennec"
	fennec_hunter.appearance = 0
	fennec_hunter.position = test_pos + Vector2(-48.0, 22.0)
	fennec_hunter.home = fennec_hunter.position
	woodland_pop._residents.add_child(fennec_hunter)

	var jerboa_prey: WoodlandMammal = mammal_scene.instantiate() as WoodlandMammal
	jerboa_prey.name = "TestJerboaPrey"
	jerboa_prey.species = "jerboa"
	jerboa_prey.appearance = 0
	jerboa_prey.position = test_pos + Vector2(12.0, 24.0)
	jerboa_prey.home = jerboa_prey.position
	woodland_pop._residents.add_child(jerboa_prey)
	await get_tree().physics_frame
	_check(not fennec_hunter._rest_hours() and not jerboa_prey._rest_hours(), "fennec and jerboa are wide awake at night")

	var hunt_ok: bool = events.begin_event("fennec_hunt", fennec_hunter, jerboa_prey)
	_check(hunt_ok and fennec_hunter.mood == WoodlandMammal.Mood.LISTEN, "WildlifeEvents starts fennec_hunt with big-eared LISTEN")
	events.finish_event("test_done")
	jerboa_prey.position = test_pos
	jerboa_prey._moving = false
	jerboa_prey._danger = false
	jerboa_prey._issue(WoodlandMammal.Mood.REST, 1.0)
	jerboa_prey.hear_external_alarm(test_pos + Vector2(-24.0, 0.0))
	_check(jerboa_prey.mood == WoodlandMammal.Mood.FLEE, "jerboa bolts into zigzag FLEE upon hearing foot-drum alarm")

	# =========================================================================
	# Stufe 3 & Stufe 4b Verification: Sun-Heat, Magical Desert Weather, Caravan Road, Rare Ores & Active Ruins
	# =========================================================================
	await _verify_heat_weather_and_ruins(world, plants)

	for sc: Vector2i in sample_chunks:
		world._unload_chunk(sc)
	world._unload_chunk(test_chunk)
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


func _inspect_desert_wildlife(root: Node, allowed: Array[String], seen: Dictionary, foreign: Array[String]) -> void:
	if root is Node2D:
		var pos: Vector2 = (root as Node2D).global_position
		if BiomeBlend.arid_at(pos) >= 0.35:
			if root is WoodlandMammal:
				var wm: WoodlandMammal = root as WoodlandMammal
				if allowed.has(wm.species):
					seen[wm.species] = int(seen.get(wm.species, 0)) + 1
				else:
					foreign.append("WoodlandMammal:%s" % wm.species)
			elif root is WildCorvid:
				var wc: WildCorvid = root as WildCorvid
				if allowed.has(wc.species):
					seen[wc.species] = int(seen.get(wc.species, 0)) + 1
				else:
					foreign.append("WildCorvid:%s" % wc.species)
			elif root is TinyWildlife:
				var tw: TinyWildlife = root as TinyWildlife
				if allowed.has(tw.species):
					seen[tw.species] = int(seen.get(tw.species, 0)) + 1
				else:
					foreign.append("TinyWildlife:%s" % tw.species)
			elif root is RiverAnimal or root is WildRabbit or root is WildBear or root is MeadowButterfly or root is LeafCritter:
				foreign.append(root.get_class())
	for child: Node in root.get_children():
		_inspect_desert_wildlife(child, allowed, seen, foreign)


func _count_unlit_desert_wildlife(root: Node, allowed: Array[String]) -> void:
	if root is WoodlandMammal and allowed.has((root as WoodlandMammal).species):
		var spr: Sprite2D = root.get_node_or_null("Sprite2D") as Sprite2D
		if spr != null and (spr.material == Unlit.material() or (spr.material is CanvasItemMaterial and (spr.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED)):
			_check(false, "desert mammal %s has unlit glow material" % (root as WoodlandMammal).species)
	elif root is WildCorvid and allowed.has((root as WildCorvid).species):
		var spr_b: Sprite2D = root.get_node_or_null("Sprite2D") as Sprite2D
		if spr_b != null and (spr_b.material == Unlit.material() or (spr_b.material is CanvasItemMaterial and (spr_b.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED)):
			_check(false, "desert bird %s has unlit glow material" % (root as WildCorvid).species)
	for child: Node in root.get_children():
		_count_unlit_desert_wildlife(child, allowed)


func _verify_heat_weather_and_ruins(world: WorldLevel, plants: Dictionary) -> void:
	# 1. Caravan Road Decals (`desert_caravan_south`, `desert_caravan_oases`, `desert_caravan_ruins`)
	var baked_decals: Array = DataRegistry.table("ground_baked").get("decals", []) as Array
	var caravan_ids: Dictionary = {}
	for d_v: Variant in baked_decals:
		var d: Dictionary = d_v as Dictionary
		var did: String = String(d.get("id", ""))
		if did.begins_with("desert_caravan_"):
			caravan_ids[did] = d.has("glow") and ResourceLoader.exists(String(d.get("texture", ""))) and ResourceLoader.exists(String(d.get("glow", "")))
	_check(caravan_ids.size() == 3 and bool(caravan_ids.get("desert_caravan_south", false)) and bool(caravan_ids.get("desert_caravan_oases", false)) and bool(caravan_ids.get("desert_caravan_ruins", false)), "all 3 ancient desert caravan road stretches are baked with rune-seam glow masks (%s)" % str(caravan_ids))

	var caravan_stone: int = 0
	var caravan_sand_gap: int = 0
	for path_v: Variant in DataRegistry.table("ground").get("paths", []) as Array:
		var p_spec: Dictionary = path_v as Dictionary
		if not bool(p_spec.get("quartz_caravan", false)):
			continue
		var centre_px: Vector2 = Vector2(world._start) * 16.0 + Vector2(8.0, 8.0)
		var pts: Array = p_spec.get("points", []) as Array
		for i: int in range(pts.size() - 1):
			var pa: Vector2 = centre_px + Vector2(float((pts[i] as Array)[0]), float((pts[i] as Array)[1]))
			var pb: Vector2 = centre_px + Vector2(float((pts[i + 1] as Array)[0]), float((pts[i + 1] as Array)[1]))
			for st: int in 4:
				var sample_p: Vector2 = pa.lerp(pb, float(st) / 4.0)
				var s_name: String = Terrain.surface_at(sample_p)
				if s_name == "stone":
					caravan_stone += 1
				elif s_name == "sand" or s_name == "quartz":
					caravan_sand_gap += 1
	_check(caravan_stone >= 20 and caravan_sand_gap >= 15, "caravan trail alternates exposed stone slabs (%d) with wind-buried sand gaps (%d)" % [caravan_stone, caravan_sand_gap])

	# 2. Rare Ores (`prism_vein`, `ruin_sandstone`) & New Items (`prism_shard`, `ruin_stone`)
	var items_tbl: Dictionary = DataRegistry.table("items")
	_check(items_tbl.has("prism_shard") and items_tbl.has("ruin_stone"), "items.json defines prism_shard and ruin_stone")
	_check(plants.has("prism_vein") and plants.has("ruin_sandstone"), "plants.json defines prism_vein and ruin_sandstone")

	var pvein: Rock = (load(String(plants.prism_vein.scene)) as PackedScene).instantiate() as Rock
	pvein.setup(world, Vector2i(845, 175), "prism_vein", 1)
	add_child(pvein)
	var pv_solid: bool = not pvein._body_shape.disabled and not pvein.is_depleted()
	pvein.apply_state({"h": pvein.slots(), "k": "prism_vein"}, "strip")
	await get_tree().process_frame
	_check(pv_solid and pvein.is_depleted() and pvein._body_shape.disabled, "prism_vein mines cleanly to walkable crystal rubble")
	pvein.queue_free()

	var rstone: Rock = (load(String(plants.ruin_sandstone.scene)) as PackedScene).instantiate() as Rock
	rstone.setup(world, Vector2i(846, 175), "ruin_sandstone", 0)
	add_child(rstone)
	var rs_solid: bool = not rstone._body_shape.disabled and not rstone.is_depleted()
	rstone.apply_state({"h": rstone.slots(), "k": "ruin_sandstone"}, "strip")
	await get_tree().process_frame
	_check(rs_solid and rstone.is_depleted() and rstone._body_shape.disabled, "ruin_sandstone mines cleanly to walkable sandstone rubble")
	rstone.queue_free()

	# Verify prism_vein never spawns off ground quartz and fits real generated outcrops
	TimeManager.set_time(0.50)
	var open_sand_px: Vector2 = Vector2(840, 175) * 16.0 + Vector2(8.0, 8.0)
	for try_s: int in 120:
		var cand_s: Vector2 = Vector2(780 + (try_s % 20) * 3, 145 + (try_s / 20) * 4) * 16.0 + Vector2(8.0, 8.0)
		if BiomeBlend.arid_at(cand_s) > 0.80 and BiomeBlend.oasis_at(cand_s) < 0.02 and not BiomeBlend.is_quartz_surface(cand_s) and not DesertHeat.is_in_shade(get_tree(), cand_s) and world._relief.flat_around(cand_s, 36.0) and world.water_depth(cand_s) < 0.0:
			open_sand_px = cand_s
			break
	var open_quartz_px: Vector2 = Vector2.ZERO
	for cy_q: int in range(3, 8):
		for cx_q: int in range(23, 31):
			var rect_q: Rect2i = Rect2i(Vector2i(cx_q, cy_q) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			for entry_q: Dictionary in world._generator.props_for_chunk(rect_q):
				var ek: String = String(entry_q.kind)
				if (ek == "prism_vein" or ek == "sun_quartz_rock") and not DesertHeat.is_in_shade(get_tree(), entry_q.pos as Vector2):
					var p_q: Vector2 = entry_q.pos as Vector2
					if world._generator._prism_vein_fits(p_q, 0):
						open_quartz_px = p_q
						break
			if open_quartz_px != Vector2.ZERO:
				break
		if open_quartz_px != Vector2.ZERO:
			break
	_check(not world._generator._prism_vein_fits(open_sand_px, 0) and open_quartz_px != Vector2.ZERO, "prism_vein rejects open sand and fits real white ground-quartz outcrops (%s)" % str(open_quartz_px / 16.0))

	# 3. Sun-Heat (`DesertHeat`, shade, quartz 50% rate, oasis wading, cooling fruits & stamina modifiers)
	TimeManager.set_time(0.50) ## peak midday sun
	var sand_drive: float = DesertHeat.heat_drive(get_tree(), open_sand_px)
	var quartz_drive: float = DesertHeat.heat_drive(get_tree(), open_quartz_px)
	TimeManager.set_time(0.0) ## cool desert night
	var night_drive: float = DesertHeat.heat_drive(get_tree(), open_sand_px)
	_check(sand_drive > 0.04 and night_drive < -0.10, "DesertHeat builds heat in midday sun (%.3f) and cools at night (%.3f)" % [sand_drive, night_drive])
	_check(quartz_drive > 0.0 and quartz_drive < sand_drive * 0.62, "standing on cool white ground quartz halves heat buildup (quartz=%.3f vs sand=%.3f)" % [quartz_drive, sand_drive])

	TimeManager.set_time(0.50)
	var arch_test: DesertRuins.QuartzArch = DesertRuins.QuartzArch.new()
	arch_test.setup(open_sand_px, 0)
	add_child(arch_test)
	await get_tree().process_frame
	var shade_spot: Vector2 = open_sand_px + Vector2(12.0, -8.0)
	var arch_shades: bool = DesertHeat.is_in_shade(get_tree(), shade_spot)
	var shade_drive: float = DesertHeat.heat_drive(get_tree(), shade_spot)
	_check(arch_shades and shade_drive < -0.20, "QuartzArch casts real cooling ground shade (in_shade=%s, drive=%.3f)" % [str(arch_shades), shade_drive])

	# Player heat stamina, oasis wading & edible fruit cooling check
	var test_player: Player = (load("res://src/entities/player/player.tscn") as PackedScene).instantiate() as Player
	test_player.name = "99"
	test_player.position = Vector2(798, 209) * 16.0 + Vector2(8.0, 8.0)
	add_child(test_player)
	test_player.set_physics_process(false)
	_check(DesertHeat.is_in_cooling_water(test_player), "oasis lagoon/pond registers as cooling water for player")
	test_player.position = open_sand_px + Vector2(80.0, 0.0)
	var base_step_cost: float = test_player.step_cost()
	var base_sprint: float = test_player.stamina.sprint_scale()
	var base_regen: float = test_player.stamina.regen_scale()
	test_player.heat_amount = 1.0
	test_player.effects.apply("sun_heat")
	var hot_step_cost: float = test_player.step_cost()
	var hot_sprint: float = test_player.stamina.sprint_scale()
	var hot_regen: float = test_player.stamina.regen_scale()
	_check(is_equal_approx(hot_regen, base_regen * 0.70) and is_equal_approx(hot_sprint, base_sprint * 1.15) and is_equal_approx(hot_step_cost, base_step_cost * 1.15), "full sun_heat applies -30%% stamina regen and +15%% sprint & shadow-step cost")
	test_player.health.current = test_player.health.max_health
	var date_def: Dictionary = DataRegistry.get_entry("items", "sun_date")
	var date_stats: Dictionary = date_def.get("stats", {}) as Dictionary
	_check(int(date_stats.get("cools", 0)) > 0 and InventoryComponent.usable(test_player, date_def), "cooling desert fruit (sun_date) can be eaten even at full HP while heated")
	test_player.cool_down(40.0)
	_check(test_player.heat_amount == 0.0 and not test_player.effects.has("sun_heat") and test_player.effects.has("refreshed") and test_player.stamina.regen_scale() > base_regen, "cool_down clears sun_heat immediately and grants refreshed (+15%% stamina regen)")
	test_player.queue_free()

	# 4. Magical Desert Weather (`RESONANZWIND` & `QUARZGEWITTER`) + Obelisk / Conduit / Seal Synergy
	var wm2: WeatherManager = WeatherManager.current
	if wm2 != null:
		wm2.focus = open_quartz_px
		wm2.force("downpour", 0.0)
		for _s1: int in 6:
			wm2.follow(false, 4.0)
		var res_rate_q: float = DesertHeat.spell_recharge_rate(get_tree(), open_quartz_px)
		var res_ok: bool = wm2.desert_resonance > 0.7 and wm2.rain == 0.0 and wm2.ground_wet == 0.0 and wm2.display_name() == "RESONANZWIND" and res_rate_q > 1.18
		_check(res_ok, "global rain becomes dry Singender Resonanzwind in desert with faster spell recharge on quartz (res=%.2f, rate=%.2f, name=%s)" % [wm2.desert_resonance, res_rate_q, wm2.display_name()])

		wm2.force("storm", 0.0)
		for _s2: int in 6:
			wm2.follow(false, 4.0)
		var struck_positions: Array[Vector2] = []
		var on_arc: Callable = func(at_p: Vector2, _info: Dictionary) -> void: struck_positions.append(at_p)
		wm2.arcane_lightning_struck.connect(on_arc)
		wm2._strike({"x": 0.56, "y": 0.44, "far": 0.1, "seed": 7, "bolt": true, "double": false}, 0.0)
		wm2.arcane_lightning_struck.disconnect(on_arc)
		var storm_rate: float = DesertHeat.spell_recharge_rate(get_tree(), open_sand_px)
		var storm_ok: bool = wm2.desert_arcane_storm > 0.4 and wm2.rain == 0.0 and wm2.puddle == 0.0 and wm2.display_name() == "QUARZGEWITTER" and not struck_positions.is_empty() and storm_rate >= 1.30
		_check(storm_ok, "global storm becomes dry Arkanes Quarzgewitter with violet-amber arcane lightning & +35%% spell recharge (storm=%.2f, strikes=%d, rate=%.2f)" % [wm2.desert_arcane_storm, struck_positions.size(), storm_rate])
		wm2.release()

	# 5. Active Ruin Magic (`DesertRuins`: Bundled Architectural Ensembles ONLY, ZERO lone scattered rune pieces)
	_check(world.desert_ruins != null and world.desert_ruins.site_count() >= 10, "DesertRuins plans active bundled ruin ensembles across Sonnenquarz-Öde (sites=%d)" % (world.desert_ruins.site_count() if world.desert_ruins != null else 0))
	if world.desert_ruins != null:
		var all_ensembles_valid: bool = true
		var allowed_kinds: Array[String] = ["gate_courtyard", "shrine_ensemble", "sanctum_seal"]
		var masonry_cells: Dictionary = {}
		for m_entry: Dictionary in world.desert_ruins.extra_masonry():
			masonry_cells[m_entry.cell as Vector2i] = true
		for c_key: Variant in world.desert_ruins.sites():
			var s_spec: Dictionary = world.desert_ruins.sites()[c_key] as Dictionary
			if not (String(s_spec.get("kind", "")) in allowed_kinds):
				all_ensembles_valid = false
		_check(all_ensembles_valid and not masonry_cells.is_empty(), "every DesertRuins site uses a multi-piece architectural blueprint with bundled corner masonry (masonry=%d)" % masonry_cells.size())

		# Verify 100% of generated `ruin_sandstone` props across desert chunks come exclusively from bundled ruin ensembles (0 lone scattered blocks)
		var total_ruin_blocks: int = 0
		var stray_ruin_blocks: int = 0
		for cy_r: int in range(3, 9):
			for cx_r: int in range(22, 33):
				var rect_r: Rect2i = Rect2i(Vector2i(cx_r, cy_r) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
				for prop_r: Dictionary in world._generator.props_for_chunk(rect_r):
					if String(prop_r.kind) == "ruin_sandstone":
						total_ruin_blocks += 1
						var cell_r: Vector2i = Vector2i((prop_r.pos as Vector2) / 16.0)
						if not masonry_cells.has(cell_r):
							stray_ruin_blocks += 1
		_check(total_ruin_blocks >= 12 and stray_ruin_blocks == 0, "ruin_sandstone spawns exclusively inside bundled ruin ensembles (%d bundled, %d stray)" % [total_ruin_blocks, stray_ruin_blocks])

		# Populate one real DesertRuins chunk and verify >= 3 coordinated ruin nodes spawn together
		var first_ruin_chunk: Vector2i = world.desert_ruins.sites().keys()[0] as Vector2i
		world.desert_ruins.populate_chunk(first_ruin_chunk)
		var spawned_nodes: Array = world.desert_ruins._live_chunks.get(first_ruin_chunk, []) as Array
		_check(spawned_nodes.size() >= 3, "populating a DesertRuins chunk spawns a cohesive multi-node ensemble (nodes=%d)" % spawned_nodes.size())
		world.desert_ruins.free_chunk(first_ruin_chunk)

	var ob_harm: DesertRuins.ResonanceObelisk = DesertRuins.ResonanceObelisk.new()
	ob_harm.setup(open_sand_px + Vector2(0.0, 90.0), 0)
	add_child(ob_harm)
	var ob_over: DesertRuins.ResonanceObelisk = DesertRuins.ResonanceObelisk.new()
	ob_over.setup(open_sand_px + Vector2(180.0, 90.0), 2)
	add_child(ob_over)
	var cond_test: DesertRuins.LightConduit = DesertRuins.LightConduit.new()
	cond_test.setup(open_sand_px + Vector2(0.0, 20.0), open_sand_px + Vector2(0.0, 90.0), true)
	cond_test.target_node = ob_harm
	add_child(cond_test)
	await get_tree().process_frame
	var passive_ob_rate: float = DesertHeat.spell_recharge_rate(get_tree(), ob_harm.global_position + Vector2(12.0, 0.0))
	cond_test.on_spell_cast(open_sand_px + Vector2(0.0, 22.0), open_sand_px + Vector2(0.0, 22.0), "banish")
	var pulsed_ok: bool = cond_test.is_pulsing()
	for _step_c: int in 16:
		cond_test._process(0.08)
	var energized_ob_rate: float = DesertHeat.spell_recharge_rate(get_tree(), ob_harm.global_position + Vector2(12.0, 0.0))
	ob_over.energize(8.0)
	_check(pulsed_ok and ob_harm.is_energized() and passive_ob_rate >= 1.30 and energized_ob_rate > passive_ob_rate and ob_over.is_emitting_ring(), "LightConduit carries spell pulse into ResonanceObelisk (+35%% -> +60%% recharge & Overcharged Prism Ring)")

	arch_test.queue_free()
	ob_harm.queue_free()
	ob_over.queue_free()
	cond_test.queue_free()

	# Verify placed PrismSeal WorldTrials (`prism_sonnenquarz` & `prism_ruinenfeld`)
	var puzzles_node: Puzzles = world.get_node_or_null("Puzzles") as Puzzles
	_check(puzzles_node != null, "WorldLevel attaches Puzzles node")
	if puzzles_node != null:
		for pid: String in ["prism_sonnenquarz", "prism_ruinenfeld"]:
			var ptrial: PrismSeal = puzzles_node.trial(pid) as PrismSeal
			_check(ptrial != null and ptrial.reward_rise() and ptrial._arch != null and ptrial._conduits.size() == 3 and ptrial._corner_glows.size() == 4, "Puzzles builds %s as full PrismSeal sanctuary ensemble (arch + 3 orthogonal conduits + 4 corner piers)" % pid)
			if ptrial != null:
				var p_home: Vector2 = ptrial.global_position
				_check(world.water_depth(p_home) < 0.0 and world._relief.flat_around(p_home, 108.0), "%s sits on wide dry flat desert ground (%s)" % [pid, str(p_home / 16.0)])
		var solve_trial: PrismSeal = puzzles_node.trial("prism_sonnenquarz") as PrismSeal
		if solve_trial != null:
			solve_trial.activate_pillar(0)
			solve_trial.activate_pillar(1)
			solve_trial.activate_pillar(2)
			await get_tree().process_frame
			var chests_node: LootChests = LootChests.of(get_tree())
			_check(puzzles_node.is_solved("prism_sonnenquarz") and chests_node != null and chests_node.chest("trial_prism_sonnenquarz") != null, "lighting all 3 PrismSeal obelisks solves the trial and raises reward LootChest from the sand")

	print("DESERT: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

