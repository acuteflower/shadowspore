extends Node
## End-to-end verification & visual capture for `SlashWorldFx` and `LivingGrass` gating.
##
## Headless QA: Godot --headless --path . --fixed-fps 60 res://tools/test_slash_world_fx.tscn
## Visual QA:   Godot --rendering-driver opengl3 --path . --fixed-fps 60 res://tools/test_slash_world_fx.tscn -- --capture=/abs/dir

const GRASS_LAB_SCENE: PackedScene = preload("res://tools/grass_lab.tscn")

var _fails: int = 0
var _checks: int = 0
var _capture_dir: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
	_run.call_deferred()


func _chk(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_fails += 1
		push_error("FAIL: " + msg)
		print("FAIL: ", msg)


func _all_living_grass_motes(root: Node) -> int:
	var total: int = 0
	for n: Node in get_tree().get_nodes_in_group("living_grass"):
		if n is LivingGrass:
			var lg: LivingGrass = n as LivingGrass
			if lg._mote_layer != null:
				total += lg._mote_layer.motes.size()
	return total


func _clear_all_living_grass_motes() -> void:
	for n: Node in get_tree().get_nodes_in_group("living_grass"):
		if n is LivingGrass:
			var lg: LivingGrass = n as LivingGrass
			if lg._mote_layer != null:
				lg._mote_layer.motes.clear()


func _has_kind(fx: SlashWorldFx, kind: int) -> bool:
	return fx.last_mote_kinds.has(kind)


func _save_shot(filename: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		img.save_png(_capture_dir.path_join(filename))


func _wait_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _run() -> void:
	var lab: GrassLab = GRASS_LAB_SCENE.instantiate() as GrassLab
	lab._demo_active = false
	add_child(lab)
	await _wait_frames(8)

	var player: Player = lab._player
	_chk(player != null and player.attack != null, "GrassLab player & AttackComponent initialized")
	if player == null:
		get_tree().quit(1)
		return
	if lab._ui_layer != null:
		lab._ui_layer.visible = false
	lab._zoom_macro = not _capture_dir.is_empty()
	lab._apply_camera_zoom()

	var fx: SlashWorldFx = SlashWorldFx.of(player.attack)
	_chk(fx != null, "SlashWorldFx singleton attaches cleanly to active scene")
	var exclude: Array[RID] = [player.get_rid()]

	# 1. BEACH SAND (Square -2 dry beach): sand fan, ZERO green grass snippets, ZERO LivingGrass motes!
	var beach_pt: Vector2 = Vector2(-690.0, 20.0)
	for x_scan: int in range(-800, -610, 8):
		var cand: Vector2 = Vector2(float(x_scan), 16.0)
		if Terrain.surface_at(cand) == "beach_sand" and not lab._grass.has_grass_near(cand):
			beach_pt = cand
			break
	_clear_all_living_grass_motes()
	fx.clear_motes()
	lab._move_player_for_shot(beach_pt)
	player.reset_physics_interpolation()
	player.facing = Vector2.RIGHT
	await _wait_frames(3)
	fx.on_swing_sweep(beach_pt, Vector2.RIGHT, 26.0, 1.8, -1.0, "slash", "sword_1h", exclude)
	_chk(
		_has_kind(fx, SlashWorldFx.MoteKind.SAND_GRAIN) and not _has_kind(fx, SlashWorldFx.MoteKind.GRASS_SNIPPET),
		"Beach sand swing spawns SAND_GRAIN and zero GRASS_SNIPPET (surf=%s, mats=%s)" % [Terrain.surface_at(beach_pt), str(fx.last_materials)]
	)
	_chk(_all_living_grass_motes(lab) == 0, "Beach swing leaks zero LivingGrass motes across all 3 patches")
	if not _capture_dir.is_empty():
		await _wait_frames(4)
		await _save_shot("01_beach_sand_slash_2x.png")

	# 2. SHADOW STEP ON BEACH SAND: zero LivingGrass motes!
	_clear_all_living_grass_motes()
	player.play_shadow_step(beach_pt, beach_pt + Vector2(20.0, 0.0), Vector2.RIGHT)
	await _wait_frames(3)
	_chk(_all_living_grass_motes(lab) == 0, "Shadow Step on bare beach sand spawns zero green LivingGrass motes")
	player._step_t = -1.0

	# 3. WET SAND (Coastal swash): damp sand + water, ZERO green grass!
	var wet_pt: Vector2 = Vector2.ZERO
	var found_wet: bool = false
	for x_scan: int in range(-960, -580, 2):
		var cand: Vector2 = Vector2(float(x_scan), 12.0)
		if Terrain.surface_at(cand) == "wet_sand":
			wet_pt = cand
			found_wet = true
			break
	if found_wet:
		fx.clear_motes()
		fx.on_swing_sweep(wet_pt, Vector2.UP, 20.0, 1.2, 1.0, "slash", "sword_1h", exclude)
		_chk(
			_has_kind(fx, SlashWorldFx.MoteKind.SAND_GRAIN) and not _has_kind(fx, SlashWorldFx.MoteKind.GRASS_SNIPPET),
			"Wet sand swing spawns damp SAND_GRAIN and zero GRASS_SNIPPET (surf=%s, mats=%s)" % [Terrain.surface_at(wet_pt), str(fx.last_materials)]
		)
	else:
		_chk(false, "Could not locate wet_sand band on Square -2 coast")

	# 4. BROOK WATER (Day + Night bioluminescence + WaterField wave wake!): ZERO green grass!
	var water_pt: Vector2 = Vector2(-384.0, -78.0)
	for y_scan: int in range(-110, 110, 6):
		var cand: Vector2 = Vector2(-384.0, float(y_scan))
		if Terrain.surface_at(cand) in ["shallow_water", "deep_water", "tide_shallow"]:
			water_pt = cand
			break
	fx.clear_motes()
	lab._move_player_for_shot(water_pt + Vector2(22.0, 0.0))
	player.reset_physics_interpolation()
	player.facing = Vector2.LEFT
	await _wait_frames(3)
	lab._water_field.recenter_wave_field(water_pt)
	fx.on_swing_sweep(water_pt + Vector2(12.0, 0.0), Vector2.LEFT, 26.0, 1.8, -1.0, "slash", "sword_1h", exclude)
	_chk(
		_has_kind(fx, SlashWorldFx.MoteKind.WATER_DROP) and not _has_kind(fx, SlashWorldFx.MoteKind.GRASS_SNIPPET),
		"Water swing spawns WATER_DROP and zero GRASS_SNIPPET (surf=%s, mats=%s)" % [Terrain.surface_at(water_pt), str(fx.last_materials)]
	)
	_chk(lab._water_field._wave_active, "Water swing carves live wave impulse into WaterField ringbuffer")
	if not _capture_dir.is_empty():
		await _wait_frames(3)
		await _save_shot("02_water_slash_day_2x.png")

	# Night bioluminescent water spray
	lab._apply_time(3) ## Night (0.00)
	fx.clear_motes()
	fx.on_heavy_impact(water_pt + Vector2(16.0, 0.0), Vector2.LEFT, 28.0, "sword_1h", exclude)
	_chk(
		_has_kind(fx, SlashWorldFx.MoteKind.WATER_DROP) and _has_kind(fx, SlashWorldFx.MoteKind.GLINT_UNLIT),
		"Night heavy water slam spawns WATER_DROP + unlit bioluminescent GLINT_UNLIT"
	)
	if not _capture_dir.is_empty():
		await _wait_frames(3)
		await _save_shot("03_water_heavy_night_bio_2x.png")
	lab._apply_time(0) ## Back to noon

	# 5. ANCIENT STONE CROSSROADS (Square 2): stone chips/dust + heavy sparks, ZERO green grass!
	var stone_pt: Vector2 = Vector2(384.0, 6.0)
	fx.clear_motes()
	lab._move_player_for_shot(stone_pt - Vector2(18.0, 0.0))
	player.reset_physics_interpolation()
	player.facing = Vector2.RIGHT
	await _wait_frames(3)
	fx.on_heavy_impact(stone_pt - Vector2(20.0, 0.0), Vector2.RIGHT, 28.0, "sword_1h", exclude)
	_chk(
		_has_kind(fx, SlashWorldFx.MoteKind.SPARK_HOT) and _has_kind(fx, SlashWorldFx.MoteKind.STONE_CHIP) and not _has_kind(fx, SlashWorldFx.MoteKind.GRASS_SNIPPET),
		"Ancient stone heavy chop spawns SPARK_HOT + STONE_CHIP and zero GRASS_SNIPPET (mats=%s)" % str(fx.last_materials)
	)
	if not _capture_dir.is_empty():
		await _wait_frames(3)
		await _save_shot("04_stone_heavy_sparks_2x.png")

	# 6. SANCTUARY RUIN WAYMARKER SOLID CONTACT (Layer 1 stone object -> unlit steel sparks!)
	var ruin_pos: Vector2 = Vector2(304.0, -14.0)
	fx.clear_motes()
	lab._move_player_for_shot(ruin_pos + Vector2(-18.0, 4.0))
	player.reset_physics_interpolation()
	player.facing = Vector2.RIGHT
	await _wait_frames(3)
	fx.on_swing_sweep(ruin_pos + Vector2(-18.0, 2.0), Vector2.RIGHT, 26.0, 1.8, -1.0, "slash", "sword_1h", exclude)
	_chk(
		fx.last_objects.has("stone") and _has_kind(fx, SlashWorldFx.MoteKind.SPARK_HOT),
		"Swinging into SanctuaryRuin detects 'stone' collider and emits SPARK_HOT (objs=%s)" % str(fx.last_objects)
	)
	if not _capture_dir.is_empty():
		await _wait_frames(3)
		await _save_shot("05_sanctuary_ruin_sparks_2x.png")

	# 7. LUSH LIVING MEADOW + FLORAL ZONE (Square 1 NW): torn grass snippets + flower petals!
	var meadow_pt: Vector2 = Vector2(-90.0, -60.0)
	fx.clear_motes()
	lab._move_player_for_shot(meadow_pt)
	player.reset_physics_interpolation()
	player.facing = Vector2.RIGHT
	await _wait_frames(3)
	fx.on_swing_sweep(meadow_pt, Vector2.RIGHT, 26.0, 1.8, -1.0, "slash", "sword_1h", exclude)
	_chk(
		_has_kind(fx, SlashWorldFx.MoteKind.GRASS_SNIPPET),
		"Lush living meadow swing spawns directional GRASS_SNIPPET (mats=%s)" % str(fx.last_materials)
	)
	if not _capture_dir.is_empty():
		await _wait_frames(3)
		await _save_shot("06_meadow_grass_petals_2x.png")

	# 8. WOODLAND FLOOR (Square 3): fluttering autumn leaves + humus!
	var forest_pt: Vector2 = Vector2(720.0, 0.0)
	for x_scan: int in range(620, 880, 8):
		var cand: Vector2 = Vector2(float(x_scan), 0.0)
		if Terrain.surface_at(cand) == "forest_floor":
			forest_pt = cand
			break
	fx.clear_motes()
	lab._move_player_for_shot(forest_pt)
	player.reset_physics_interpolation()
	player.facing = Vector2.RIGHT
	await _wait_frames(3)
	fx.on_swing_sweep(forest_pt, Vector2.RIGHT, 26.0, 1.8, -1.0, "slash", "sword_1h", exclude)
	_chk(
		_has_kind(fx, SlashWorldFx.MoteKind.PETAL_OR_LEAF) and _has_kind(fx, SlashWorldFx.MoteKind.MUD_SPLAT),
		"Woodland forest_floor swing spawns fluttering autumn leaves & humus (surf=%s)" % Terrain.surface_at(forest_pt)
	)
	if not _capture_dir.is_empty():
		await _wait_frames(3)
		await _save_shot("07_forest_leaves_humus_2x.png")

	# 9. SILVER BIRCH TRUNK SOLID CONTACT (Square 4N): white paper-bark wood splinters!
	var birch: LivingTree = lab._birch_mother
	if birch != null and is_instance_valid(birch):
		var b_pos: Vector2 = birch.global_position
		fx.clear_motes()
		lab._move_player_for_shot(b_pos + Vector2(-20.0, 2.0))
		player.reset_physics_interpolation()
		player.facing = Vector2.RIGHT
		await _wait_frames(3)
		fx.on_swing_sweep(b_pos + Vector2(-20.0, 2.0), Vector2.RIGHT, 28.0, 1.8, -1.0, "slash", "sword_1h", exclude)
		_chk(
			fx.last_objects.has("living_tree") and _has_kind(fx, SlashWorldFx.MoteKind.WOOD_SPLINTER),
			"Swinging into Silver Birch trunk detects 'living_tree' and spawns WOOD_SPLINTER (objs=%s)" % str(fx.last_objects)
		)
		if not _capture_dir.is_empty():
			await _wait_frames(3)
			await _save_shot("08_birch_bark_splinters_2x.png")

	# 10. SIMULATION CLEANUP: motes step cleanly and auto-sleep (`is_processing() == false`)!
	for _s: int in 90:
		fx._process(0.025)
	_chk(fx.active_mote_count() == 0 and not fx.is_processing(), "SlashWorldFx drains cleanly and disables _process() when idle")

	print("SLASH WORLD FX: %d checks, %d failures" % [_checks, _fails])
	if _fails == 0:
		print("SLASH WORLD FX OK")
	get_tree().quit(0 if _fails == 0 else 1)
