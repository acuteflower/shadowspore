extends Node2D
## Live OpenGL3 visual verification & showcase capture for the Textured Pixel-Art FX & Spawn Overhaul
## of `Aurelith, Herz des Sonnenquarzes` (`boss_aurelith`):
## 1) `aurelith_combat_1_stage1_magic.png`: Terraced quicksand vortex, 4 varied monoliths, organic sintered crusts, colossal buried gauntlet + rune chain, astrolabe Resonanz-Kern & arcing geode pod!
## 2) `aurelith_combat_2_cleave_and_seams.png`: Sweeping crystal crescent cleave arcs, sprouting crossed sun-quartz fault seams, Sun-Architect telegraphs & faceted shrapnel!
## 3) `aurelith_combat_3_stage2_prism_beam.png`: Rotating Solar Astrolabe muzzle lens, braided `SOLAR_BEAM` refracting 3 ways off a QuartzGolem + superheated molten-cracked pillar cover!
## 4) `aurelith_combat_4_stage2_temple_press.png`: Carved pharaonic sandstone relief crushing-walls (`TEMPLE_PRESS`) clamping inward with gold cornices & sun-quartz fangs!
## 5) `aurelith_combat_5_stage3_tsunami_armillary.png`: Billowing `DUNE_TSUNAMI` sand-wave barrels, chevron wind-shadow shelters, engraved golden Armillary rings & forked sky-lightning!
## 6) `aurelith_combat_6_victory_reliquary_hologram.png`: Victory — `AurelithHologram`, legendary `Glutreliquiar` chest & textured `PRISMENBRUCH` cathedral cluster + shrapnel burst!

const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")


func _ready() -> void:
	_run.call_deferred()


func _parse_dir() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			return a.substr(6)
	return ""


func _clear_damage_numbers(world: Node) -> void:
	for ch: Node in world.get_children():
		if ch is DamageNumber:
			ch.queue_free()
	for ch2: Node in get_children():
		if ch2 is DamageNumber:
			ch2.queue_free()


func _shot(dir: String, file_name: String, world: Node) -> void:
	_clear_damage_numbers(world)
	for _f: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, file_name])


func _wait_sec(sec: float) -> void:
	var t: float = 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _run() -> void:
	var out_dir: String = _parse_dir()
	NetworkManager.host_singleplayer()
	var world: WorldLevel = WORLD_SCENE.instantiate() as WorldLevel
	world.opening_over = true
	add_child(world)
	for _i: int in 5:
		await get_tree().physics_frame
		await get_tree().process_frame

	var arena: AurelithArena = world.aurelith_arena
	var spot: Vector2 = arena.basin_position()
	var hero: Player = world._players.get_child(0) as Player
	hero.intro = null
	hero.story_lock = false
	hero.wounded = false
	hero.health.max_health = 9999.0
	hero.health.current = 9999.0
	for c: Node in hero.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for wc: Node in world.get_children():
		if wc is CanvasLayer:
			(wc as CanvasLayer).visible = false
	var hero_cam: Camera2D = hero.get_node_or_null("Camera2D") as Camera2D
	if hero_cam != null:
		hero_cam.enabled = false

	var cam: Camera2D = Camera2D.new()
	cam.enabled = true
	cam.position = spot + Vector2(0.0, -14.0)
	cam.zoom = Vector2(0.86, 0.86)
	add_child(cam)

	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.54
	hero.request_teleport(spot + Vector2(-88.0, 86.0))
	await _wait_sec(0.75)

	arena._clear_guardians()
	for s_i: int in arena._slot_dead.size():
		arena._slot_dead[s_i] = true
	arena.killed_count = arena._guardian_specs.size()
	arena.summon_boss(true)
	arena.on_boss_fist_slam()
	arena._wall_grow = 1.0
	arena._update_wall_animation(0.016)
	await _wait_sec(0.25)

	var boss: Aurelith = arena.boss
	var field: AurelithField = boss.field
	var fight: AurelithFight = boss.fight
	fight.set_physics_process(false)
	boss.set_physics_process(false)

	# --- SHOT 1: Stage 1 Ground Magic, 4 Varied Pillars, Organic Crusts, Buried Gauntlet + Rune Chain & Astrolabe Core ---
	boss.global_position = spot + Vector2(-14.0, -18.0)
	boss.heading = 0.50
	boss.rig().start_pose(AurelithRig.Pose.GAUNTLET_SLAM, 1.0, 0.65)
	boss.rig().set_detached_fist(true, true, spot + Vector2(96.0, 48.0), 0.0)
	field.set_gauntlet_anchor(true, boss.global_position, spot + Vector2(96.0, 48.0), 5.0)
	field.warn_box(spot + Vector2(96.0, 48.0), boss.global_position, 20.0, 4.0)
	field.add_quicksand(spot + Vector2(-114.0, 34.0), 74.0, 8.0, 0.0)
	field.add_quartz_plate(spot + Vector2(28.0, -40.0), 30.0, 10.0)
	field.add_quartz_plate(spot + Vector2(-26.0, 42.0), 25.0, 10.0)
	# 3 distinct monolith architectures within the clean `<= 3` arena pillar cap!
	field.spawn_pillar(1, spot + Vector2(-108.0, -44.0), 20.0)
	field.spawn_pillar(2, spot + Vector2(118.0, -34.0), 20.0)
	field.spawn_pillar(3, spot + Vector2(-42.0, -76.0), 20.0)
	field.spawn_resonance_core(1, spot + Vector2(-34.0, 74.0), 10.0)
	field.spawn_geode_pod(boss.global_position + Vector2(0.0, -48.0), spot + Vector2(58.0, -64.0), 0.75)
	var g1: Node2D = fight._spawn_battle_golem_host(spot + Vector2(54.0, -56.0), 0)
	if g1 != null:
		g1.set_physics_process(false)
		field.set_tether_links([{"a": boss.global_position + Vector2(0, -42), "b": g1.global_position + Vector2(0, -14), "col": AurelithField.TURQ_SAFE}])
	await _wait_sec(0.28)
	await _shot(out_dir, "aurelith_combat_1_stage1_magic", world)

	# --- SHOT 2: Crystal Crescent Cleave Arcs, Sprouting Crossed Sun-Quartz Seams & Engraved Cone Telegraph ---
	TimeManager.time_of_day = 0.62
	field.clear_all()
	fight._clear_battle_golems()
	boss.rig().set_detached_fist(true, false)
	boss.rig().twin_blades = true
	boss.global_position = spot + Vector2(-22.0, -6.0)
	boss.heading = 0.35
	boss.rig().start_pose(AurelithRig.Pose.BLADE_CLEAVE, 1.0, 0.42)
	field.spawn_pillar(1, spot + Vector2(-118.0, -32.0), 20.0)
	field.spawn_pillar(4, spot + Vector2(126.0, -40.0), 20.0)
	field.warn_cone(boss.global_position, 0.35, 1.08, 102.0, 0.9)
	field.spawn_slash_arc(boss.global_position + Vector2(56.0, 14.0), 0.35, 1.38, 0.85, false)
	field.spawn_slash_arc(boss.global_position + Vector2(28.0, -8.0), 0.55, 1.12, 0.36, true)
	# Erupted X-bomb sun-quartz crystal ridges on the right + incoming Sun-Architect X-telegraph on the lower-left!
	var xb_center: Vector2 = spot + Vector2(96.0, 42.0)
	for arm_i: int in 2:
		var xa: float = 0.28 + float(arm_i) * PI * 0.5 + PI * 0.25
		var xd: Vector2 = Vector2(cos(xa) * 58.0, sin(xa) * 58.0 * AurelithField.SQUASH)
		field.add_crystal_seam(xb_center - xd * 0.92, xb_center + xd * 0.92, 1.8)
	var xb_warn: Vector2 = spot + Vector2(-106.0, 52.0)
	for arm_w: int in 2:
		var wa: float = float(arm_w) * PI * 0.5 + PI * 0.25
		var wd_v: Vector2 = Vector2(cos(wa) * 44.0, sin(wa) * 44.0 * AurelithField.SQUASH)
		field.warn_box(xb_warn - wd_v, xb_warn + wd_v, 13.0, 0.9, AurelithField.GOLD_WARN)
	field.spawn_shrapnel(xb_center, 10, 0.95)
	hero.request_teleport(spot + Vector2(-42.0, 68.0))
	await _wait_sec(0.18)
	await _shot(out_dir, "aurelith_combat_2_cleave_and_seams", world)

	# --- SHOT 3: Stage 2 `SOLAR_BEAM` Astrolabe Muzzle Lens, 3-Way Golem Prism Refraction & Superheated Molten Pillar ---
	TimeManager.time_of_day = 0.73
	field.clear_all()
	fight._clear_battle_golems()
	boss.rig().twin_blades = false
	boss.rig().prism_release = 1.0
	boss.rig().charge_intensity = 0.9
	boss.global_position = spot + Vector2(-76.0, -12.0)
	var beam_ang: float = 0.24
	boss.heading = beam_ang
	boss.rig().start_pose(AurelithRig.Pose.CHEST_BEAM, 2.0, 0.9)
	var prism_golem_pos: Vector2 = boss.global_position + Vector2(0, -24) + Vector2.from_angle(beam_ang) * 116.0
	var g2: Node2D = fight._spawn_battle_golem_host(prism_golem_pos, 2)
	if g2 != null:
		g2.set_physics_process(false)
	field.spawn_pillar(2, spot + Vector2(114.0, 56.0), 20.0)
	field.spawn_pillar(3, spot + Vector2(-10.0, -70.0), 20.0)
	# Heat pillar 2 so its glowing Row-1 molten-gold cracks are clearly visible!
	if field._pillars.has(2):
		(field._pillars[2] as AurelithField.PillarNode).beam_heat = 0.85
	field.add_quartz_plate(prism_golem_pos, 28.0, 12.0)
	field.spawn_resonance_core(2, spot + Vector2(-106.0, 62.0), 10.0)
	field.launch_core_at_boss(2, 1)
	var splits: Array[Dictionary] = []
	for k: int in [-1, 0, 1]:
		var sa: float = beam_ang + float(k) * 0.72
		splits.append({
			"from": prism_golem_pos + Vector2(0, -10),
			"to": prism_golem_pos + Vector2.from_angle(sa) * 158.0,
			"col": AurelithField.TURQ_SAFE if k != 0 else AurelithField.GOLD_WARN,
		})
	field.set_solar_beam(true, boss.global_position + Vector2(0, -24), beam_ang, 122.0, splits)
	hero.request_teleport(spot + Vector2(146.0, 66.0))
	await _wait_sec(0.24)
	await _shot(out_dir, "aurelith_combat_3_stage2_prism_beam", world)

	# --- SHOT 4: Stage 2 Pharaonic Sandstone Relief `TEMPLE_PRESS` Crushing-Walls ---
	TimeManager.time_of_day = 0.60
	cam.zoom = Vector2(0.90, 0.90)
	field.clear_all()
	fight._clear_battle_golems()
	boss.global_position = spot + Vector2(-68.0, -34.0)
	boss.heading = 0.48
	boss.rig().prism_release = 1.0
	boss.rig().start_pose(AurelithRig.Pose.CLAP_PREP, 1.2, 0.75)
	var press_center: Vector2 = spot + Vector2(42.0, 28.0)
	var press_axis: Vector2 = Vector2(0.32, 0.947).normalized()
	var press_tang: Vector2 = Vector2(-press_axis.y, press_axis.x)
	field.add_temple_press_visual(press_center, press_axis, 118.0, 48.0, 1.4)
	field.warn_box(press_center - press_tang * 59.0, press_center + press_tang * 59.0, 46.0, 1.4)
	field.spawn_pillar(1, spot + Vector2(-128.0, 42.0), 20.0)
	field.spawn_pillar(4, spot + Vector2(138.0, -36.0), 20.0)
	hero.request_teleport(press_center + Vector2(-6.0, 4.0))
	await _wait_sec(0.30)
	await _shot(out_dir, "aurelith_combat_4_stage2_temple_press", world)

	# --- SHOT 5: Stage 3 Textured `DUNE_TSUNAMI` Rollers, Chevron Shelters, Engraved Armillary & Forked Lightning ---
	TimeManager.time_of_day = 0.80
	cam.zoom = Vector2(0.76, 0.76)
	field.clear_all()
	fight._clear_battle_golems()
	boss.global_position = spot + Vector2(0.0, -6.0)
	boss.heading = PI * 0.5
	boss.rig().prism_release = 1.0
	boss.rig().storm_ascension = 1.0
	boss.rig().twin_blades = true
	boss.rig().charge_intensity = 1.0
	boss.rig().start_pose(AurelithRig.Pose.ZENITH_CHARGE, 2.0, 1.0)
	field.set_zenith_seal(true, boss.global_position, 0.85)
	field.spawn_pillar(1, spot + Vector2(-92.0, -18.0), 20.0)
	field.spawn_pillar(3, spot + Vector2(74.0, 38.0), 20.0)
	field.spawn_pillar(4, spot + Vector2(22.0, -72.0), 20.0)
	field.set_tsunami_wave(true, Vector2.RIGHT, -0.42)
	field.warn_armillary(5.0, 0.42)
	field.spawn_sky_bolt(spot + Vector2(-132.0, 54.0), AurelithField.GOLD_WARN, 0.9)
	field.spawn_sky_bolt(spot + Vector2(142.0, -34.0), AurelithField.TURQ_SAFE, 0.9)
	hero.request_teleport(spot + Vector2(-48.0, -18.0))
	await _wait_sec(0.24)
	await _shot(out_dir, "aurelith_combat_5_stage3_tsunami_armillary", world)

	# Live OpenGL3 360° Stage-3 Rotation Zero-Allocation Proof (renders real _draw_body + _draw_glow frames!)
	var cache_before_spin: int = AurelithRig._TEX_CACHE.size()
	boss.rig().start_pose(AurelithRig.Pose.MOVE, 2.0)
	for spin_i: int in 12:
		var ang_s: float = TAU * float(spin_i) / 12.0
		boss.heading = ang_s
		boss.rig().update_rig(0.02, Vector2.from_angle(ang_s) * 145.0, ang_s)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if AurelithRig._TEX_CACHE.size() != cache_before_spin:
		push_error("AURELITH_RIG_CACHE_LEAK: grew from %d to %d during 360° Stage-3 spin!" % [cache_before_spin, AurelithRig._TEX_CACHE.size()])

	# --- SHOT 5B: Cinematic Phase Transition (`DIE SONNENSCHMELZE` — Wiped Arena + BossPhaseScreen + Sky-Bolts!) ---
	TimeManager.time_of_day = 0.76
	cam.enabled = false
	if hero_cam != null:
		hero_cam.enabled = true
	field.clear_all()
	fight._clear_battle_golems()
	boss.global_position = spot + Vector2(0.0, 4.0)
	boss.heading = PI * 0.5
	boss.rig().prism_release = 1.0
	boss.rig().storm_ascension = 1.0
	boss.rig().twin_blades = true
	boss.rig().charge_intensity = 1.0
	boss.rig().start_pose(AurelithRig.Pose.ZENITH_CHARGE, 2.2, 1.0)
	boss.rig().update_rig(0.02, Vector2.ZERO, PI * 0.5)
	hero.request_teleport(spot + Vector2(0.0, 108.0))
	var tr2: Dictionary = fight._transition_cfg(2)
	var demo_ps: BossPhaseScreen = BossPhaseScreen.play(boss, hero, String(tr2.get("text", "DIE SONNENSCHMELZE")), tr2)
	# Step live through `scream_at` (`1.55 s`) + `title_at` (`2.05 s`) to `2.45 s` so letterbox + zoomed camera + VoidTitle are in full glory!
	var ps_t: float = 0.0
	var fired_burst_shot: bool = false
	while ps_t < 2.45:
		await get_tree().process_frame
		ps_t += get_process_delta_time()
		if not fired_burst_shot and ps_t >= 2.15:
			fired_burst_shot = true
			field.set_zenith_seal(true, boss.global_position, 0.92)
			field.add_quartz_plate(boss.global_position, 48.0, 12.0)
			for b_i: int in 3:
				var ba: float = TAU * float(b_i) / 3.0 - PI * 0.5
				var bp: Vector2 = boss.global_position + Vector2(cos(ba) * 62.0, sin(ba) * 62.0 * AurelithField.SQUASH)
				field.spawn_sky_bolt(bp, AurelithField.GOLD_WARN if b_i != 1 else AurelithField.TURQ_SAFE, 0.72)
			field.spawn_shrapnel(boss.global_position + Vector2(0.0, -24.0), 12, 1.08)
	if is_instance_valid(demo_ps):
		demo_ps._flash_left = 0.0
		demo_ps._flash_next = 99.0
		demo_ps._push_shader()
	await _shot(out_dir, "aurelith_combat_5b_phase_transition", world)
	if is_instance_valid(demo_ps):
		demo_ps._finish()
	if hero_cam != null:
		hero_cam.enabled = false
	cam.enabled = true

	# --- SHOT 6: Monumental 4-Beat Death Finale (Beat 3: Sun-Prism Supernova & Split-Obelisk Visage Cleave!) ---
	TimeManager.time_of_day = 0.78
	cam.zoom = Vector2(0.92, 0.92)
	cam.position = spot + Vector2(0.0, -24.0)
	field.clear_all()
	fight._clear_battle_golems()
	boss.global_position = spot + Vector2(0.0, 6.0)
	boss.heading = PI * 0.5
	boss.mode = Aurelith.Mode.DEAD
	boss._death_age = 0.0
	boss._death_beats.clear()
	boss.rig().prism_release = 1.0
	boss.rig().storm_ascension = 1.0
	boss.rig().twin_blades = false
	boss.rig().charge_intensity = 0.0
	boss.rig().start_pose(AurelithRig.Pose.DEAD, 3.80)
	field.set_zenith_seal(true, boss.global_position, 0.85)
	hero.request_teleport(spot + Vector2(-92.0, 62.0))
	# Advance live through Beats 1, 2 & into Beat 3 Supernova + Cleaved Obelisk (`~2.28 s` / `p = 0.60`)!
	var sim_dt: float = 1.0 / 60.0
	var target_supernova_t: float = 2.28
	var sim_elapsed: float = 0.0
	while sim_elapsed < target_supernova_t:
		boss._death_age += sim_dt
		boss._step_death_fx(sim_dt)
		boss.rig().update_rig(sim_dt, Vector2.ZERO, PI * 0.5)
		sim_elapsed += sim_dt
	await _shot(out_dir, "aurelith_combat_6_epic_death_supernova", world)

	# --- SHOT 7: Monumental Death Beat 4 — Cleaved Obelisk Halves Dissolving into Ascending Starlight & Sand Motes ---
	while sim_elapsed < 3.16:
		boss._death_age += sim_dt
		boss._step_death_fx(sim_dt)
		boss.rig().update_rig(sim_dt, Vector2.ZERO, PI * 0.5)
		sim_elapsed += sim_dt
	await _shot(out_dir, "aurelith_combat_7_epic_death_dissolve", world)

	# --- SHOT 8: Victory — Released Basin, `AurelithHologram`, Legendary `Glutreliquiar` & Textured `PRISMENBRUCH` ---
	TimeManager.time_of_day = 0.68
	cam.zoom = Vector2(0.95, 0.95)
	cam.position = spot + Vector2(0.0, -10.0)
	field.clear_all()
	boss.queue_free()
	arena.boss = null
	arena.on_released()
	arena._wall_grow = 0.0
	for td: Dictionary in arena._wall_teeth:
		(td["root"] as Node2D).visible = false
	var holo: AurelithHologram = arena.hologram()
	if holo != null:
		holo.set_active(true)
		holo._appear = 1.0
		holo._burst = 0.0

	var chests_sys: LootChests = LootChests.of(get_tree())
	if chests_sys != null:
		chests_sys.boss_chest("boss_aurelith", "legendary", spot + Vector2(0.0, 48.0), {"copper": 480, "xp": 460, "winners": [1], "items": [], "relics": []}, 0.05)
	hero.request_teleport(spot + Vector2(-56.0, 44.0))
	var sp_cathedral: PrismSpikeFx = PrismSpikeFx.spawn(world, hero, spot + Vector2(-96.0, 46.0), {"delay": 4.0, "damage": 28.0, "radius": 56.0, "knockback": 150.0})
	if sp_cathedral != null:
		sp_cathedral._age = 3.0
	var sp_shatter: PrismSpikeFx = PrismSpikeFx.spawn(world, hero, spot + Vector2(96.0, 42.0), {"delay": 0.42, "damage": 28.0, "radius": 56.0, "knockback": 150.0})
	if sp_shatter != null:
		sp_shatter._age = 0.0
	await _wait_sec(0.56)
	await _shot(out_dir, "aurelith_combat_8_victory_reliquary_hologram", world)

	print("AURELITH COMBAT PREVIEW OK (cache=%d)" % AurelithRig._TEX_CACHE.size())
	get_tree().quit(0)
