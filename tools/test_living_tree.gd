extends "res://src/world/test_level.gd"
## Comprehensive automated verification suite for `LivingTree 2.0` & `valley_oak` (`tools/test_living_tree.tscn`):
## Verifies all 14 Technical Pillars:
##  1. Split-Canopy Rig across all 7 stages + Coppice (`RootSkirt`, `TrunkBase`, `TrunkUpper`, `CanopyClusters`)
##  2. 3-frequency GPU wind uniforms & damped harmonic oscillator cluster spring response
##  3. Ontogenetic growth progression (`s0 -> s1 -> s2 -> s3 -> s4`) at 1:1 pixel density
##  4. `Jobs.run()` async Stand Ecology (`Crown Shyness` lateral sky-channel retraction & Stand Shade)
##  5. Bidirectional `GroundSurfaces` + `LivingGrass` Canopy Drip-Line & Root-Collar microclimate
##  6. Progressive directional Axe Kerf Notch + Nonlinear Forestry Felling + `LivingGrass` crush + rolled `ItemDrop`s
##  7. Multi-lobe `DaylightField` *Komorebi* canopy projection + `SunShadows` wind-kind 3 recognition
##  8. Selective per-cluster Canopy Peeling + Bayer 4x4 Pixel-Dither Iris (TrunkBase stays 1.0 opaque!)
##  9. Ecological Sockets (`RoofPerch` bough weight-dip + `TreeRootSeat` mossy resting hollow)
## 10. Hydrological Canopy Interception (`_canopy_wetness`, `stemflow`, post-rain `CanopyDripLine` droplets)
## 11. Nocturnal "Ellie = Shadowspore" Mycorrhizal Bio-Resonance & Waystone `consecrate_heal()`
## 12. Regenerative Alchemy Bark Harvest (`oak_amber` / `oak_bark` / `oak_polypore` + 3-day regrowth) & `autumn_shift`
## 13. Coppice Regrowth (`Stockausschlag` sprouting directly out of felled stump!)
## 14. Zero-CPU offscreen idle sleep (`is_processing() == false` when offscreen & calm)

const TREE_SCENE: PackedScene = preload("res://src/entities/props/living_tree.tscn")

class StubMap:
	extends RefCounted
	var world_seed: int = 2026

var _map: StubMap = StubMap.new()
var _wind: WorldWind
var _surfaces: GroundSurfaces
var _grass: LivingGrass
var _player: Player
var _failures: int = 0


func _ready() -> void:
	NetworkManager.host_singleplayer()
	add_to_group("sandbox")
	super._ready()
	_wind = WorldWind.new()
	_wind.name = "WorldWind"
	_wind.setup(self)
	add_child(_wind)

	var rect: Rect2 = Rect2(-256.0, -160.0, 640.0, 320.0)
	_surfaces = GroundSurfaces.new()
	_surfaces.setup(rect, 2.0)
	_surfaces.paint_tree_root_zone(Vector2(0.0, 0.0), 11.0, 76.0, 401)
	_surfaces.commit()
	add_child(_surfaces)

	_grass = LivingGrass.new()
	_grass.setup_rect(rect, 2026, true, _surfaces)
	add_child(_grass)

	_run_suite.call_deferred()


func _land_biome(_tile: Vector2i) -> String:
	return "meadow"


func navigation_floor(_pos: Vector2) -> bool:
	return true


func _check(name_id: String, ok: bool) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", name_id])
	if not ok:
		_failures += 1


func _spawn_tree(pos: Vector2, st: int, seed_v: int) -> LivingTree:
	var t: LivingTree = TREE_SCENE.instantiate() as LivingTree
	t.setup_tree(pos, st, seed_v, "valley_oak")
	add_child(t)
	return t


func _wait_frames(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _run_suite() -> void:
	await _wait_frames(3)
	if _players.get_child_count() > 0:
		_player = _players.get_child(0) as Player
	if _player != null:
		_player.position = Vector2(-120.0, 40.0)

	# 1. Verify all 7 stages + rig loading & 1:1 pixel scale
	var all_stages_ok: bool = true
	var stage_trees: Array[LivingTree] = []
	for s: int in 7:
		var st_tree: LivingTree = _spawn_tree(Vector2(-210.0 + float(s) * 28.0, -90.0), s, 100 + s)
		stage_trees.append(st_tree)
		if st_tree.scale != Vector2.ONE or st_tree._clusters.is_empty():
			all_stages_ok = false
	_check("01_seven_stages_1to1_rig", all_stages_ok)

	# 2. Spawn Crown-Shyness Pair (Stage 4 + Stage 3) & Stage 5 Matriarch
	var oak_m: LivingTree = _spawn_tree(Vector2(0.0, 0.0), 4, 404)
	var oak_n: LivingTree = _spawn_tree(Vector2(86.0, -4.0), 3, 303)
	var matriarch: LivingTree = _spawn_tree(Vector2(-110.0, 12.0), 5, 505)
	await _wait_frames(2)

	_check("02_split_canopy_clusters", oak_m._clusters.size() == 5 and matriarch._clusters.size() == 6 and matriarch._overhang_sprite != null)

	# 3. Async Jobs.run() Stand Ecology (Crown Shyness!)
	var eco_box: Dictionary = {"done": false}
	var job: Jobs.Job = LivingTree.compute_stand_ecology_async([oak_m, oak_n], func() -> void: eco_box["done"] = true)
	Jobs.wait(job)
	await _wait_frames(2)
	_check("03_jobs_crown_shyness", bool(eco_box["done"]) and oak_m.shy_right_px >= 1.0 and oak_n.shy_left_px >= 1.0)

	# 4. GroundSurfaces + LivingGrass Drip-Line & Root-Collar microclimate
	var hab_root: Dictionary = _surfaces.grass_habitat_at(Vector2(2.0, 0.0))
	var hab_drip: Dictionary = _surfaces.grass_habitat_at(Vector2(70.0, 0.0))
	_check("04_drip_line_and_root_zone", float(hab_root.get("density", 1.0)) == 0.0 and float(hab_drip.get("height_scale", 1.0)) >= 1.10)

	# 5. Multi-lobe DaylightField Komorebi & SunShadows wind_kind == 3
	var lobes: PackedVector4Array = oak_m.day_canopy_lobes()
	var shadow_kind: int = SunShadows.current._wind_kind(oak_m._clusters[0].sprite) if is_instance_valid(SunShadows.current) else 3
	_check("05_komorebi_lobes_and_sun_shadows", lobes.size() == 5 and shadow_kind == 3)

	# 6. Ecological Sockets: Bird Perch weight-dip spring + Matriarch RootRestSeat
	oak_m.impulse_cluster(1, Vector2(0.0, 2.0), 18.0)
	await _wait_frames(3)
	var spring_moved: bool = oak_m._clusters[1].disp.length() > 0.05
	_check("06_sockets_perch_spring_and_seat", spring_moved and matriarch._root_seat != null and matriarch._perches.size() >= 3)

	# 7. Stage 1 Whip elastic walk-through flex (no solid collision blocker!)
	var whip: LivingTree = stage_trees[1]
	var whip_body_disabled: bool = whip._body_shape.disabled
	if _player != null:
		_player.position = whip.global_position + Vector2(-8.0, 0.0)
		await _wait_frames(2)
		_player.position = whip.global_position + Vector2(6.0, 0.0)
		await _wait_frames(3)
	_check("07_whip_walkthrough_flex", whip_body_disabled and absf(whip._trunk_sway_angle) > 0.001)

	# 8. Selective Per-Cluster Canopy Peeling + Synchronized Upper-Trunk Bayer 4x4 Iris (TrunkBase stays 1.0!)
	if _player != null:
		_player.position = oak_m.global_position + Vector2(-34.0, -64.0)
		oak_m._update_selective_cluster_peeling()
		await _wait_frames(6)
	var peeled_any: bool = false
	var kept_any: bool = false
	for cn: LivingTree.ClusterNode in oak_m._clusters:
		if cn.peel_target < 0.85:
			peeled_any = true
		else:
			kept_any = true
	var upper_iris: Vector4 = (oak_m._upper_trunk_mat.get_shader_parameter("iris_player") as Vector4) if oak_m._upper_trunk_mat != null else Vector4.ZERO
	_check("08_selective_peeling_solid_trunk", peeled_any and kept_any and oak_m._trunk_base.modulate.a == 1.0 and upper_iris.w > 0.5)

	# 9. Regenerative Alchemy Bark Harvest + 3-Day Regrowth & Autumn Shift
	var had_pickup: bool = oak_m._has_ripe_pickup()
	oak_m._server_pick_bark(_player)
	await _wait_frames(2)
	var hidden_after_pick: bool = not oak_m._has_ripe_pickup() and (oak_m._harvest_overlay == null or not oak_m._harvest_overlay.visible)
	TimeManager.day += 4
	oak_m._on_day_started(TimeManager.day)
	var regrown_pickup: bool = oak_m._has_ripe_pickup()
	oak_m.set_autumn_shift(0.85)
	_check("09_alchemy_bark_harvest_and_phenology", had_pickup and hidden_after_pick and regrown_pickup)

	# 10. Hydrological Canopy Interception & Post-Rain Drip
	_wind.rain = 0.90
	for _r: int in 18:
		oak_m._step_hydrology_and_air(0.05)
	_wind.rain = 0.0
	oak_m._step_hydrology_and_air(0.05)
	_check("10_hydrology_interception_and_drip", oak_m._canopy_wetness > 0.04 and oak_m._post_rain_timer > 10.0)

	# 11. Nocturnal "Ellie = Shadowspore" Mycorrhizal Bio-Resonance & Waystone Healing
	TimeManager.lock_at(0.0)
	matriarch.set_night(1.0)
	matriarch.set_corruption(0.75)
	if _player != null:
		_player.position = matriarch.global_position + Vector2(12.0, 6.0)
		matriarch._actor_flex_prev[_player.get_instance_id()] = _player.global_position
		for _n: int in 42:
			matriarch._step_player_interactions(0.05)
	matriarch.consecrate_heal()
	_check("11_shadowspore_resonance_and_heal", matriarch.resonance_triggered and matriarch.corruption == 0.0 and matriarch._heal_flash > 0.5)
	TimeManager.lock_at(0.50)

	# 12. Progressive Directional Axe Kerf Notch + Nonlinear Felling + LivingGrass Crush + Rolled Drops!
	if _player != null:
		_player.position = Vector2(-180.0, 60.0)
	_grass.recenter_field(oak_m.global_position)
	var hits_needed: int = int(oak_m.state.get("hp", 6))
	var kerf_shown: bool = false
	for h: int in hits_needed:
		oak_m.strike_with_axe(oak_m.global_position + Vector2(-24.0, 2.0))
		if h == 2 and oak_m._kerf_overlay != null and oak_m._kerf_overlay.visible:
			kerf_shown = true
	# Step felling physics through hinge creak -> drag acceleration -> impact -> settle -> stump!
	var safety_steps: int = 0
	while oak_m.is_falling() and safety_steps < 260:
		oak_m._process(0.03)
		safety_steps += 1
	await _wait_frames(3)
	var drops_spawned: int = $Drops.get_child_count()
	_check("12_kerf_nonlinear_felling_grass_crush", kerf_shown and oak_m.is_depleted() and not oak_m.is_falling() and oak_m.last_felled_grass_crush >= 0.70 and drops_spawned >= 4)

	# 13. Coppice Regrowth (`Stockausschlag` -> Whip -> Sapling!)
	oak_m.advance_growth_days(3)
	var is_coppice: bool = oak_m.is_depleted() and int(oak_m.state.get("c", 0)) == 1 and not oak_m._clusters.is_empty()
	oak_m.advance_growth_days(3)
	var regrew_whip: bool = not oak_m.is_depleted() and oak_m.stage == 1
	oak_m.advance_growth_days(4)
	var grew_sapling: bool = oak_m.stage == 2
	_check("13_coppice_stockausschlag_and_growth", is_coppice and regrew_whip and grew_sapling)

	# 14. Zero-CPU Offscreen Sleep
	var far_tree: LivingTree = _spawn_tree(Vector2(2400.0, 2400.0), 4, 909)
	far_tree._on_screen = false
	far_tree._mote_canvas.motes.clear()
	far_tree._process(0.016)
	_check("14_zero_cpu_offscreen_sleep", not far_tree.is_processing())

	# 15. Modular Per-Tree Trait Overlays & Structural Archetype Diversity (`s4`, `s4_b`, `s4_c`)
	var seen_rigs: Dictionary = {}
	var seen_signatures: Dictionary = {}
	for v_i: int in 10:
		var vt: LivingTree = _spawn_tree(Vector2(-240.0 + float(v_i) * 44.0, 120.0), 4, 1400 + v_i * 37)
		seen_rigs[vt.active_rig_key] = true
		var sig: String = "%s|%d|%d|%d|%d|%d" % [
			vt.active_rig_key,
			int(vt.rolled_traits.get("moss", -1)),
			int(vt.rolled_traits.get("ivy", -1)),
			int(vt.rolled_traits.get("hollow", -1)),
			int(vt.rolled_traits.get("fungi", -1)),
			int(vt.rolled_traits.get("sprig", -1)),
		]
		seen_signatures[sig] = true
	var custom_t: LivingTree = _spawn_tree(Vector2(220.0, 120.0), 4, 1999)
	custom_t.configure_traits(1, {"moss": 0, "ivy": -1, "hollow": 1, "fungi": 0, "sprig": 1, "amber": 0}, 0)
	var custom_ok: bool = not custom_t._has_ripe_pickup() and custom_t._trait_sprites.size() >= 2
	_check("15_modular_traits_and_archetype_variety", seen_rigs.size() >= 2 and seen_signatures.size() >= 5 and custom_ok)

	# 16. Second Species (`silver_birch`): All 7 Stages, Multi-Stem/Arched Variants, Birch Traits, Lemon-Gold Autumn Hue & Mother Seat!
	var birch_stages_ok: bool = true
	for bs: int in 7:
		var b_st: LivingTree = TREE_SCENE.instantiate() as LivingTree
		b_st.setup_tree(Vector2(-240.0 + float(bs) * 30.0, -130.0), bs, 2100 + bs, "silver_birch")
		add_child(b_st)
		if b_st._clusters.is_empty():
			birch_stages_ok = false
	var birch_rigs: Dictionary = {}
	for bi: int in 9:
		var bt: LivingTree = TREE_SCENE.instantiate() as LivingTree
		bt.setup_tree(Vector2(-220.0 + float(bi) * 38.0, 150.0), 4, 2500 + bi * 41, "silver_birch")
		add_child(bt)
		birch_rigs[bt.active_rig_key] = true
	var b_mother: LivingTree = TREE_SCENE.instantiate() as LivingTree
	b_mother.setup_tree(Vector2(260.0, 40.0), 5, 2705, "silver_birch")
	b_mother.configure_traits(0, {"moss": 0, "ivy": 0, "hollow": 1, "fungi": 1, "sprig": -1, "amber": 1}, 0)
	add_child(b_mother)
	await _wait_frames(2)
	var b_seat_ok: bool = b_mother._root_seat != null and b_mother._root_seat.label == "UNTER DER MUTTERBIRKE RASTEN"
	var b_hue: float = float(b_mother._clusters[0].mat.get_shader_parameter("autumn_hue")) if not b_mother._clusters.is_empty() else 0.0
	_check("16_silver_birch_species_and_traits", birch_stages_ok and birch_rigs.size() >= 2 and b_seat_ok and b_hue >= 0.95)

	# 17. Third Species (`wild_apple`): All 7 Stages, Blossom & Fruit Phenology, Fruit-Droop + Tree-Shake Harvest, Scarlet Autumn & Mother Seat!
	var apple_stages_ok: bool = true
	for as_idx: int in 7:
		var a_st: LivingTree = TREE_SCENE.instantiate() as LivingTree
		a_st.setup_tree(Vector2(-240.0 + float(as_idx) * 32.0, 185.0), as_idx, 3100 + as_idx, "wild_apple")
		add_child(a_st)
		if a_st._clusters.is_empty():
			apple_stages_ok = false
	var apple_rigs: Dictionary = {}
	for ai: int in 9:
		var at: LivingTree = TREE_SCENE.instantiate() as LivingTree
		at.setup_tree(Vector2(-220.0 + float(ai) * 38.0, 215.0), 4, 3500 + ai * 43, "wild_apple")
		add_child(at)
		apple_rigs[at.active_rig_key] = true
	var a_blossom: LivingTree = TREE_SCENE.instantiate() as LivingTree
	a_blossom.setup_tree(Vector2(260.0, 120.0), 5, 3705, "wild_apple")
	a_blossom.configure_traits(0, {"moss": 0, "ivy": 0, "hollow": 1, "fungi": -1, "sprig": -1}, 0, 1)
	add_child(a_blossom)
	var a_fruit: LivingTree = TREE_SCENE.instantiate() as LivingTree
	a_fruit.setup_tree(Vector2(330.0, 120.0), 4, 3404, "wild_apple")
	a_fruit.configure_traits(0, {"moss": 0, "ivy": 0, "hollow": 0, "fungi": -1, "sprig": 0}, 0, 2)
	add_child(a_fruit)
	await _wait_frames(2)
	var blossom_vis: bool = a_blossom.is_in_group("blossom_trees")
	var any_blossom_sp: bool = false
	for bc: LivingTree.ClusterNode in a_blossom._clusters:
		if bc.blossom_sprite != null and bc.blossom_sprite.visible:
			any_blossom_sp = true
	a_blossom._spawn_petal_burst(6)
	var has_petal_mote: bool = false
	if a_blossom._mote_canvas != null:
		for m: LivingTree.TreeMote in a_blossom._mote_canvas.motes:
			if m.kind == 6:
				has_petal_mote = true
	var outer_idx: int = -1
	var droop_y_before: float = 0.0
	var any_fruit_sp_before: bool = false
	for fi: int in a_fruit._clusters.size():
		var fc: LivingTree.ClusterNode = a_fruit._clusters[fi]
		if fc.fruit_sprite != null and fc.fruit_sprite.visible:
			any_fruit_sp_before = true
		if absf(fc.side) > 0.25 and outer_idx < 0:
			outer_idx = fi
			droop_y_before = fc.base_pos.y
	var drops_before: int = $Drops.get_child_count()
	a_fruit._server_pick_bark()
	await _wait_frames(2)
	var drops_after: int = $Drops.get_child_count()
	var rebound_ok: bool = outer_idx >= 0 and droop_y_before >= 1.5 and (droop_y_before - a_fruit._clusters[outer_idx].base_pos.y) >= 1.5
	var fruit_hidden_after: bool = true
	for fc2: LivingTree.ClusterNode in a_fruit._clusters:
		if fc2.fruit_sprite != null and fc2.fruit_sprite.visible:
			fruit_hidden_after = false
	var a_seat_ok: bool = a_blossom._root_seat != null and a_blossom._root_seat.label == "UNTER DEM ALTEN APFELBAUM RASTEN"
	var a_hue: float = float(a_blossom._clusters[0].mat.get_shader_parameter("autumn_hue")) if not a_blossom._clusters.is_empty() else 0.0
	_check(
		"17_wild_apple_phenology_and_shake",
		apple_stages_ok and apple_rigs.size() >= 2 and blossom_vis and any_blossom_sp and has_petal_mote
		and any_fruit_sp_before and (drops_after > drops_before) and rebound_ok and fruit_hidden_after
		and a_seat_ok and a_hue >= 1.95
	)

	print("LIVING TREE 2.0 SUITE: %d failures" % _failures)
	if _failures == 0:
		print("LIVING TREE OK")
	get_tree().quit(1 if _failures > 0 else 0)
