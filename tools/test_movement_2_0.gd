extends Node2D
## Comprehensive automated verification of Shadowspore Movement & Animation 2.0 (`T1..T12`, `V1..V12`):
## Run: Godot --headless --path . res://tools/test_movement_2_0.tscn

var failures: int = 0
var passes: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		passes += 1
		print("PASS: ", label)
	else:
		failures += 1
		push_error("MOVEMENT 2.0 FAIL: " + label)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# ------------------------------------------------------------------
	# 1. Pure MovementRules & data/movement.json checks (T1, T3, T4, T5, T9)
	# ------------------------------------------------------------------
	var cfg: Dictionary = MovementRules.cfg()
	check(not cfg.is_empty() and cfg.has("curves") and cfg.has("reisetritt"), "data/movement.json loads via DataRegistry")

	# T1: First-frame micro-impulse (`0 -> >= 45%` immediately, no muddy start)
	var step1: Dictionary = MovementRules.step_velocity(Vector2.ZERO, Vector2.RIGHT, 62.0, 1.0 / 60.0, 0.01, 0.0, 0.0, 1.0)
	var v1: Vector2 = step1["velocity"] as Vector2
	check(v1.x >= 62.0 * 0.45, "T1 first-frame micro-impulse reaches >= 45%% speed immediately (%.1f px/s)" % v1.x)

	# T1: Sprint Surge boosts initial sprint above base sprint_speed
	var surge_step: Dictionary = MovementRules.step_velocity(Vector2(120.0, 0.0), Vector2.RIGHT, 124.0, 0.05, 0.2, 0.18, 0.05, 1.0)
	check((surge_step["velocity"] as Vector2).x > 128.0, "T1 Sprint Surge boosts velocity above base sprint_speed (%.1f px/s)" % (surge_step["velocity"] as Vector2).x)

	# T3: Gentle carving turn (< 65 deg) preserves >= 97% speed without axis-braking loss
	var carve_dir: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(45.0))
	var carve_res: Dictionary = MovementRules.step_velocity(Vector2(124.0, 0.0), carve_dir, 124.0, 1.0 / 60.0, 0.8, 0.0, 0.8, 1.0)
	var carve_v: Vector2 = carve_res["velocity"] as Vector2
	check(carve_v.length() >= 124.0 * 0.97 and carve_v.y > 4.0, "T3 gentle 45-deg carving turn preserves speed & rotates vector (%.1f px/s)" % carve_v.length())

	# T3: Hard 180-deg Sprint-Pivot triggers pivot state & strong counter-acceleration
	var piv_res: Dictionary = MovementRules.step_velocity(Vector2(124.0, 0.0), Vector2.LEFT, 124.0, 1.0 / 60.0, 0.8, 0.0, 0.8, 1.0)
	check(bool(piv_res["pivoted"]) and (piv_res["velocity"] as Vector2).x < 95.0, "T3 180-deg reversal at sprint speed triggers Hard Pivot")

	# T1: Speed-aware brake-glide after sustained sprint vs crisp walk stop
	var sprint_stop: Dictionary = MovementRules.step_velocity(Vector2(124.0, 0.0), Vector2.ZERO, 0.0, 1.0 / 60.0, 0.0, 0.0, 0.65, 1.0)
	var walk_stop: Dictionary = MovementRules.step_velocity(Vector2(45.0, 0.0), Vector2.ZERO, 0.0, 1.0 / 60.0, 0.0, 0.0, 0.0, 1.0)
	check(bool(sprint_stop["braking"]) and not bool(walk_stop["braking"]), "T1 sustained sprint triggers cushioned Brake-Glide while walk stops crisply")

	# T4: Directional slope kinematics (uphill < 1.0 < downhill)
	var up_k: float = MovementRules.slope_factor(0.0, 0.35, 8.0)
	var down_k: float = MovementRules.slope_factor(1.0, 0.65, 8.0)
	check(up_k < 0.95 and down_k > 1.03, "T4 slope gradient slows uphill (%.2f) and boosts downhill (%.2f)" % [up_k, down_k])

	# T5: Out-of-combat Reisetritt vs in-combat tactical stamina
	var rt_road: Dictionary = MovementRules.reisetritt_state(false, false, "path", 1.5)
	var rt_wild: Dictionary = MovementRules.reisetritt_state(false, false, "grass", 1.5)
	var rt_combat: Dictionary = MovementRules.reisetritt_state(true, false, "path", 1.5)
	check(bool(rt_road["active"]) and is_zero_approx(float(rt_road["stamina_scale"])) and float(rt_road["speed_mult"]) > 1.05, "T5 Reisetritt on roads grants 0 stamina drain & +8%% travel speed")
	check(bool(rt_wild["active"]) and float(rt_wild["stamina_scale"]) < 0.5, "T5 Reisetritt in wilderness cuts stamina drain by 65%%")
	check(not bool(rt_combat["active"]) and is_equal_approx(float(rt_combat["stamina_scale"]), 1.0), "T5 combat immediately restores 100%% tactical stamina rules")

	# T9: Combat footwork quadrants
	check(MovementRules.combat_quadrant(Vector2.RIGHT, Vector2.RIGHT) == MovementRules.Quadrant.FORWARD, "T9 forward quadrant")
	check(MovementRules.combat_quadrant(Vector2.DOWN, Vector2.RIGHT) == MovementRules.Quadrant.STRAFE_RIGHT, "T9 strafe-right quadrant")
	check(MovementRules.combat_quadrant(Vector2.UP, Vector2.RIGHT) == MovementRules.Quadrant.STRAFE_LEFT, "T9 strafe-left quadrant")
	check(MovementRules.combat_quadrant(Vector2.LEFT, Vector2.RIGHT) == MovementRules.Quadrant.BACKPEDAL, "T9 backpedal quadrant")

	# ------------------------------------------------------------------
	# 2. Live Player, Sheets, Cosmetics, Jewelry & Arm3D checks (V1..V9)
	# ------------------------------------------------------------------
	var player: Player = (load("res://src/entities/player/player.tscn") as PackedScene).instantiate() as Player
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	check(Player.AGILE_SHEET != null and Player.AGILE_SHEET.get_size() == Vector2(43.0 * 48.0, 8.0 * 56.0), "V2/V8 player_agile.png loads with expected 43x8 layout")
	check(Player.AGILE_BLOOD != null and Player.AGILE_BLOOD.get_size() == Player.AGILE_SHEET.get_size(), "player_agile_blood.png depth/blood map matches dimensions")
	check(player._rig_agile_hand.size() == 43 * 8 and player._rig_agile_shoulder.size() == 43 * 8, "hero_rig.json agile shoulder/hand points loaded (344 frames)")
	check(GripRig.frame_arm3("player_agile.png", 27).size() == 4, "hero_arm3d.json 3D arm joints mapped for player_agile.png")
	check(TalismanArt.frame_data(Player.AGILE_SHEET, 2 * 43 + 8).size() == 16, "hero_jewelry.json collar/earring anchors mapped for player_agile.png")

	for hstyle: String in ["default", "blade_bob", "storm_tail", "moon_knot", "dusk_braids", "night_bun"]:
		check(
			ResourceLoader.exists("res://assets/characters/hair/%s/player_agile.png" % hstyle)
			and ResourceLoader.exists("res://assets/characters/hair/%s/player_agile_back.png" % hstyle),
			"hairstyle '%s' modular front/back layers exist for player_agile" % hstyle
		)
	for ostyle: String in ["default", "perlenbluete"]:
		check(ResourceLoader.exists("res://assets/characters/outfits/%s/player_agile.png" % ostyle), "outfit '%s' modular layer exists for player_agile" % ostyle)

	# V2 & T9: Verify transition & strafe frame selection on Player._animate
	player.facing = Vector2.DOWN
	player._sector = 2
	player.velocity = Vector2(58.0, 0.0)
	player.locomotion.quadrant = MovementRules.Quadrant.STRAFE_LEFT
	player._walk_time = 2.4
	player._last_step = 2
	player._animate(0.0)
	check(player._sheet == Player.AGILE_SHEET_ID and player._sprite.frame == 2 * 43 + 17 + 2, "T9 combat strafe selects player_agile strafe_l frame & 60Hz blended arm")
	player.locomotion.quadrant = MovementRules.Quadrant.FORWARD

	player.locomotion.pivot_left = 0.10
	player._animate(0.0)
	check(player._sheet == Player.AGILE_SHEET_ID and (player._sprite.frame % 43) in [7, 8, 9, 10], "V2 180-deg Sprint-Pivot selects pivot clip on player_agile")
	player.locomotion.pivot_left = 0.0

	player.velocity = Vector2.ZERO
	player.locomotion.brake_left = 0.18
	player._animate(0.0)
	check(player._sheet == Player.AGILE_SHEET_ID and (player._sprite.frame % 43) in [3, 4, 5, 6], "V2 Sprint stop selects cushioned brake-settle clip on player_agile")
	player.locomotion.brake_left = 0.0

	# ------------------------------------------------------------------
	# 3. CornerNudge around grazing world colliders (T2)
	# ------------------------------------------------------------------
	player.global_position = Vector2(200.0, 200.0)
	var post: StaticBody2D = StaticBody2D.new()
	post.collision_layer = 1
	var pshape: CollisionShape2D = CollisionShape2D.new()
	var pcircle: CircleShape2D = CircleShape2D.new()
	pcircle.radius = 4.0
	pshape.shape = pcircle
	post.add_child(pshape)
	# Place obstacle grazing only her left feeler (`-y` side when heading RIGHT)
	post.global_position = (player.get_node("CollisionShape2D") as Node2D).global_position + Vector2(6.5, -5.5)
	add_child(post)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var nudged: Vector2 = player.locomotion._apply_corner_nudge(Vector2.RIGHT)
	check(nudged.y > 0.15 and nudged.x > 0.8, "T2 CornerNudge deflects smoothly around grazing obstacle (%s)" % str(nudged))
	post.queue_free()
	await get_tree().physics_frame

	# ------------------------------------------------------------------
	# 4. Glancing SporeStep wall-glide & Sun-Quartz Choker Glint (T8, V6)
	# ------------------------------------------------------------------
	var cliff: StaticBody2D = StaticBody2D.new()
	cliff.collision_layer = 1
	var cshape: CollisionShape2D = CollisionShape2D.new()
	var cbox: RectangleShape2D = RectangleShape2D.new()
	cbox.size = Vector2(120.0, 8.0)
	cshape.shape = cbox
	cliff.add_child(cshape)
	cliff.global_position = player.global_position + Vector2(20.0, -14.0)
	add_child(cliff)
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.stepper.cooldown_left = 0.0
	player.stamina.refill()
	var step_origin: Vector2 = player.global_position
	var shallow_dir: Vector2 = Vector2(1.0, -0.42).normalized() ## ~23 deg glancing into horizontal cliff
	var glided_ok: bool = player._try_shadow_step(shallow_dir)
	while player._step_t >= 0.0:
		player._animate(1.0 / 60.0)
	check(glided_ok and player.global_position.x - step_origin.x > 32.0, "T8 glancing ShadowStep slides along cliff wall instead of fizzling (dx=%.1f)" % (player.global_position.x - step_origin.x))
	check(player.move_fx._choker_glint > 0.0, "V6 condensing out of ShadowStep triggers Valdric's Sun-Quartz choker glint")
	cliff.queue_free()
	await get_tree().physics_frame

	# ------------------------------------------------------------------
	# 5. AgileTraversal Obstacle Vault & Airborne Shadow Separation (T6, V8, V12)
	# ------------------------------------------------------------------
	player.global_position = Vector2(300.0, 300.0)
	player.facing = Vector2.RIGHT
	var log_barrier: StaticBody2D = StaticBody2D.new()
	log_barrier.add_to_group("vaultable")
	log_barrier.collision_layer = 1
	var lshape: CollisionShape2D = CollisionShape2D.new()
	var lbox: RectangleShape2D = RectangleShape2D.new()
	lbox.size = Vector2(6.0, 36.0)
	lshape.shape = lbox
	log_barrier.add_child(lshape)
	log_barrier.global_position = (player.get_node("CollisionShape2D") as Node2D).global_position + Vector2(9.0, 0.0)
	add_child(log_barrier)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var offered: bool = player.agile.offer(Vector2.RIGHT, true, 1.0 / 60.0)
	check(offered and player.agile.active() and player.agile.kind() == AgileTraversal.Kind.VAULT, "T6 vaultable low obstacle offers & starts Vault on E")
	var peak_air: float = 0.0
	var saw_vault_frame: bool = false
	while player.agile.active():
		player.agile.step(1.0 / 60.0)
		player.air_height = player.agile.air_height
		player._animate(1.0 / 60.0)
		peak_air = maxf(peak_air, player.air_height)
		if player._sheet == Player.AGILE_SHEET_ID and (player._sprite.frame % 43) >= AgileTraversal.VAULT_CLIP_START:
			saw_vault_frame = true
	check(peak_air > 6.0 and saw_vault_frame and player.global_position.x > log_barrier.global_position.x + 4.0, "V8 Vault clears obstacle cleanly with airborne arc (peak=%.1f px)" % peak_air)
	log_barrier.queue_free()

	# ------------------------------------------------------------------
	# 6. LivingCamera 2.0 Deadzone & 20 Hz Remote-Peer Hermite Smoothing (T10, T11)
	# ------------------------------------------------------------------
	player.global_position = Vector2(400.0, 400.0)
	player.locomotion.reset_camera_anchor()
	player.velocity = Vector2(20.0, 0.0)
	player.global_position += Vector2(3.0, 0.0) ## Tiny 3px step inside 9px comfort deadzone
	var tiny_cam: Vector2 = player.locomotion.compute_camera_offset(0.05, true)
	check(tiny_cam.length() < 0.5, "T10 LivingCamera comfort deadzone suppresses micro-step oscillation (%.2f px)" % tiny_cam.length())

	var remote: Player = (load("res://src/entities/player/player.tscn") as PackedScene).instantiate() as Player
	remote.name = "99" ## Non-authority peer (`multiplayer.get_unique_id()` is 1)
	add_child(remote)
	remote.set_physics_process(false)
	remote.global_position = Vector2(500.0, 500.0)
	remote.velocity = Vector2(100.0, 0.0)
	remote.locomotion.step_remote_smoothing(1.0 / 60.0)
	# Simulate a 20 Hz synchronizer packet snapping global_position by +10 px
	var rendered_before: Vector2 = remote.global_position + remote.locomotion._visual_offset
	remote.global_position += Vector2(10.0, 0.0)
	var vis_off: Vector2 = remote.locomotion.step_remote_smoothing(1.0 / 60.0)
	var rendered_after: Vector2 = remote.global_position + vis_off
	check(rendered_after.distance_to(rendered_before) < 4.5 and vis_off.x < -5.0, "T11 20Hz Hermite smoothing absorbs packet jump without visual pop (off=%s)" % str(vis_off))
	for _i: int in 18:
		vis_off = remote.locomotion.step_remote_smoothing(1.0 / 60.0)
	check(vis_off.length() < 0.6, "T11 remote smoothing converges cleanly to zero (%.2f px)" % vis_off.length())

	print("MOVEMENT 2.0 OK (%d checks passed)" % passes if failures == 0 else "MOVEMENT 2.0: %d failures" % failures)
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
