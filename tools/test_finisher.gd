extends Node2D
## Comprehensive automated verification suite for the Shadowspore V2 Finisher System & Move #1 (`spider_impale_down`):
## Run: Godot --headless --path . res://tools/test_finisher.tscn

const SPIDER_SCENE: PackedScene = preload("res://src/entities/enemies/shadow_spider.tscn")
const PLAYER_SCENE: PackedScene = preload("res://src/entities/player/player.tscn")

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		push_error("FINISHER V2 FAIL: " + msg)


func _run() -> void:
	# ------------------------------------------------------------------
	# 1. Data, Audio & Multi-Layer 3D Sprite Pipeline Checks (`T1`, `T5`, `V1`..`V5`)
	# ------------------------------------------------------------------
	var tbl: Dictionary = DataRegistry.table("finishers")
	_check(not tbl.is_empty() and tbl.has("moves") and tbl.has("settings"), "data/finishers.json loads via DataRegistry")
	var move_cfg: Dictionary = FinisherRules.move_config("spider_impale_down")
	_check(int(move_cfg.get("frames", 0)) == 16 and float(move_cfg.get("duration", 0.0)) > 0.9, "spider_impale_down config valid")

	_check(FinisherRules.weapon_supports_finisher({"id": "sword_basic", "count": 1}), "sword_1h supports Finisher")
	if not DataRegistry.get_entry("items", "sword_rift").is_empty():
		_check(FinisherRules.weapon_supports_finisher({"id": "sword_rift", "count": 1}), "sword_rift (Himmelsriss) supports Finisher")
	if not DataRegistry.get_entry("items", "sword_starlight").is_empty():
		_check(FinisherRules.weapon_supports_finisher({"id": "sword_starlight", "count": 1}), "sword_starlight supports Finisher")
	_check(not FinisherRules.weapon_supports_finisher({"id": "axe_basic", "count": 1}), "axe_1h tool does not trigger sword Finisher")
	_check(not FinisherRules.weapon_supports_finisher({"id": "pickaxe_basic", "count": 1}), "pickaxe_1h tool does not trigger sword Finisher")

	for wav_name: String in ["finisher_plunge.wav", "finisher_press.wav", "finisher_rip.wav"]:
		var wav_path: String = "res://assets/audio/sfx/" + wav_name
		_check(ResourceLoader.exists(wav_path) and load(wav_path) != null, "Finisher SFX '%s' exists and loads" % wav_name)

	var surfaces: GroundSurfaces = GroundSurfaces.new()
	add_child(surfaces)
	surfaces.setup(Rect2(-256.0, -256.0, 512.0, 512.0), 2.0)
	surfaces.commit()

	var grass: LivingGrass = LivingGrass.new()
	add_child(grass)
	grass.setup_rect(Rect2(-180.0, -180.0, 360.0, 360.0), 2027, true, surfaces)

	var enemies: Node2D = Node2D.new()
	enemies.name = "Enemies"
	add_child(enemies)

	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.name = "1"
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(Player.FINISHER_SHEET != null and Player.FINISHER_SHEET.get_size() == Vector2(16.0 * 48.0, 8.0 * 56.0), "player_finisher.png loads with 16x8 48x56 layout")
	_check(Player.FINISHER_BLOOD != null and Player.FINISHER_BLOOD.get_size() == Player.FINISHER_SHEET.get_size(), "player_finisher_blood.png matches dimensions")
	_check(bool(ArmPainter.depth_source(Player.FINISHER_BLOOD).get("valid", false)), "player_finisher_blood.png carries valid 3D ArmPainter depth encoding")
	_check(player._rig_finisher_hand.size() == 16 * 8 and player._rig_finisher_shoulder.size() == 16 * 8, "hero_rig.json finisher shoulder/hand points loaded (128 frames)")
	_check(GripRig.frame_arm3("player_finisher.png", 4).size() == 4, "hero_arm3d.json 3D arm joints mapped for player_finisher.png")
	_check(TalismanArt.frame_data(Player.FINISHER_SHEET, 2 * 16 + 8).size() == 16, "hero_jewelry.json collar/earring anchors mapped for player_finisher.png")

	for hstyle: String in ["default", "blade_bob", "storm_tail", "moon_knot", "dusk_braids", "night_bun"]:
		_check(
			ResourceLoader.exists("res://assets/characters/hair/%s/player_finisher.png" % hstyle)
			and ResourceLoader.exists("res://assets/characters/hair/%s/player_finisher_back.png" % hstyle),
			"hairstyle '%s' modular front/back layers exist for player_finisher" % hstyle
		)
	for ostyle: String in ["default", "perlenbluete"]:
		_check(ResourceLoader.exists("res://assets/characters/outfits/%s/player_finisher.png" % ostyle), "outfit '%s' modular layer exists for player_finisher" % ostyle)

	# Equip basic sword in `main_hand` and ensure selected hotbar slot has no overriding tool
	player.inventory.equipment["main_hand"] = {"id": "sword_basic", "count": 1}
	player.inventory.slots[0] = {}
	player.inventory.select(0)
	player.inventory.changed.emit()
	player.health.max_health = 500.0
	player.health.current = 500.0
	InputManager.using_mouse = false
	await get_tree().physics_frame

	# ------------------------------------------------------------------
	# 2. 8-Direction Spatial Pair Resolver (`T4`: E, SE, S, SW, W, NW, N, NE)
	# ------------------------------------------------------------------
	var probe_spider: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	enemies.add_child(probe_spider)
	probe_spider.set_physics_process(false)
	await get_tree().physics_frame
	for sec_i: int in 8:
		var ang: float = float(sec_i) * (PI / 4.0)
		player.global_position = Vector2.ZERO
		probe_spider.global_position = Vector2.from_angle(ang) * 24.0
		var pair_res: Dictionary = FinisherRules.resolve_pair_positions(player, probe_spider, move_cfg)
		_check(bool(pair_res.get("valid", false)) and int(pair_res.get("sector", -1)) == sec_i, "8-sector pair resolver aligns cleanly for sector %d" % sec_i)
	probe_spider.queue_free()
	await get_tree().physics_frame

	# ------------------------------------------------------------------
	# 3. Multi-Enemy Safety Rule (`T2`): 2 Spiders Engaged -> 1st Dies Immediately, 2nd Triggers Finisher!
	# ------------------------------------------------------------------
	player.global_position = Vector2(-20.0, 0.0)
	player.facing = Vector2.RIGHT

	var sp_first: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	sp_first.position = Vector2(2.0, 0.0)
	enemies.add_child(sp_first)
	sp_first.set_physics_process(false)

	var sp_second: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	sp_second.position = Vector2(68.0, 8.0) ## Outside sword fan, inside 165 px combat radius & targeting Ellie!
	enemies.add_child(sp_second)
	sp_second.set_physics_process(false)
	await get_tree().physics_frame

	sp_first._health.current = 1.0
	sp_second._target = player
	sp_second._health.current = 48.0

	player.attack.attack(Vector2.RIGHT)
	# Wait past sword windup (`~0.12 s`) in real-time so `AttackComponent._server_swing` scores
	await get_tree().create_timer(0.16).timeout
	await get_tree().physics_frame

	_check(not player.finisher.active(), "Multi-enemy safety: killing 1st spider while 2nd is engaged MUST NOT lock Ellie into a Finisher")
	_check(sp_first._health.current <= 0.0 and sp_first.state == ShadowSpider.State.DEAD, "1st spider dies immediately without Finisher lock when another threat is present")

	# Wait for swing recovery & `_server_ready_msec` anti-spam window (`~0.35 s`)
	await get_tree().create_timer(0.38).timeout
	await get_tree().physics_frame

	# Now move `sp_second` (the LAST remaining spider in combat!) in front of Ellie at 1 HP!
	sp_second.global_position = Vector2(4.0, 0.0)
	sp_second._health.current = 1.0
	player.global_position = Vector2(-20.0, 0.0)
	player.facing = Vector2.RIGHT
	player.effects.apply("webbed", 2.0) ## Verify launching Finisher snaps boot silk!

	var seen_beats: Array[int] = []
	var beat_conn: Callable = func(_mid: String, b_idx: int) -> void:
		if not seen_beats.has(b_idx):
			seen_beats.append(b_idx)
	player.finisher.finisher_beat.connect(beat_conn)

	var xp_before: int = player.progress.xp
	player.attack.attack(Vector2.RIGHT)

	var started_ok: bool = false
	var sheet_ok: bool = false
	var row5_cracked_ok: bool = false
	var deep_embed_ok: bool = false
	var wait_elapsed: float = 0.0
	while wait_elapsed < 1.8:
		await get_tree().physics_frame
		wait_elapsed += get_physics_process_delta_time()
		if player.finisher.active():
			started_ok = true
			if player._sheet == Player.FINISHER_SHEET_ID:
				sheet_ok = true
			if is_instance_valid(sp_second) and sp_second._rig.finisher_stage == 2 and sp_second._rig._select_body_row() == 5:
				row5_cracked_ok = true
			var bpose: Dictionary = player.finisher.blade_pose(Vector3.RIGHT, Vector3.RIGHT)
			if float(bpose.get("embed", 0.0)) >= 0.35:
				deep_embed_ok = true
		elif started_ok:
			break

	player.finisher.finisher_beat.disconnect(beat_conn)

	_check(started_ok, "Last remaining enemy lethal sword blow triggers V2 Finisher")
	_check(sheet_ok, "Player switches to FINISHER_SHEET_ID (20) during Finisher")
	_check(not player.effects.has("webbed"), "Launching Finisher snaps active 'webbed' silk on Ellie's boots")
	_check(seen_beats == [1, 2, 3], "All 3 Finisher beats fired in exact order [1: Plunge, 2: Press, 3: Rip-Out] (got %s)" % [str(seen_beats)])
	_check(row5_cracked_ok, "Beat 2 Second Deep Press switches SpiderRig to Row 5 blazing cracked carapace")
	_check(deep_embed_ok, "Beat 2 Second Deep Press drives blade >= 35% deeper into carapace")
	_check(not player.finisher.active(), "Finisher completes cleanly and returns Ellie to normal control")
	_check(not is_instance_valid(sp_second) or (sp_second._health.current <= 0.0 and sp_second.state == ShadowSpider.State.DEAD), "Target spider dies at Beat 3 Rip-Out (no 1-HP leftover)")
	_check(player.progress.xp > xp_before, "Finisher kill awards full enemy XP to player")
	_check(grass.crush_at(Vector2(4.0, 0.0)) >= 0.65, "Finisher stamps radial shockwave into LivingGrass")

	# ------------------------------------------------------------------
	# 4. Boss Override Rule (`T2`): Boss Target Triggers Finisher Even With Minions Engaged + Pushes Minions Back!
	# ------------------------------------------------------------------
	await get_tree().create_timer(0.25).timeout
	await get_tree().physics_frame

	player.global_position = Vector2(80.0, 60.0)
	player.facing = Vector2.RIGHT

	var boss_sp: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	boss_sp.brood_variant = 2
	boss_sp.position = Vector2(104.0, 60.0)
	boss_sp.set_meta("finisher_boss_override", true)
	enemies.add_child(boss_sp)
	boss_sp.set_physics_process(false)

	var minion_sp: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	minion_sp.position = Vector2(138.0, 82.0)
	enemies.add_child(minion_sp)
	await get_tree().physics_frame

	boss_sp._health.current = 1.0
	minion_sp._target = player
	minion_sp._set_state(ShadowSpider.State.CHASE)

	player.attack.attack(Vector2.RIGHT)
	var boss_finisher_triggered: bool = false
	var minion_recoiled: bool = false
	var boss_wait: float = 0.0
	while boss_wait < 0.40:
		await get_tree().physics_frame
		boss_wait += get_physics_process_delta_time()
		if player.finisher.active():
			boss_finisher_triggered = true
		if is_instance_valid(minion_sp) and minion_sp.state == ShadowSpider.State.PACK_RECOIL:
			minion_recoiled = true
		if boss_finisher_triggered and minion_recoiled:
			break

	_check(boss_finisher_triggered, "Boss Override: lethal sword hit on Boss target triggers Finisher even while minions are engaged")
	_check(minion_recoiled, "Boss Finisher shockwave pushes nearby minion into PACK_RECOIL")

	# Attempt to damage Ellie during active Boss Finisher -> host grace must protect her!
	var hp_during: float = player.health.current
	player.health.take_damage(25.0, Vector2(138.0, 82.0), 80.0)
	_check(is_equal_approx(player.health.current, hp_during), "Ellie is protected by host grace invulnerability during Finisher")

	# Wait for Boss Finisher to finish cleanly
	var end_wait: float = 0.0
	while end_wait < 1.5 and player.finisher.active():
		await get_tree().physics_frame
		end_wait += get_physics_process_delta_time()
	_check(not player.finisher.active() and boss_sp._health.current <= 0.0, "Boss Finisher completes kill & restores control")

	if _failures == 0:
		print("FINISHER V2 OK: %d/%d checks passed" % [_checks, _checks])
		get_tree().quit(0)
	else:
		push_error("FINISHER V2 FAILED: %d/%d checks failed" % [_failures, _checks])
		get_tree().quit(1)
