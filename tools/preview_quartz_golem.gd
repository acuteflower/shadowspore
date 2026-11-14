extends Node
## Live OpenGL3 visual captures of `QuartzGolem` ("Quarzwächter") on white ground-quartz outcrops in Sonnenquarz-Öde:
## 1) Camouflaged `DORMANT` quartz-sandstone pile + `PEACEFUL` hovering Sun-Quartz & Prisma guardians on white ground quartz
## 2) `SHARD_VOLLEY`: 3 hovering shoulder spikes + 3 flying faceted `QuartzShard` projectiles & ground warning corridors
## 3) `SANDSTONE_SHOCK`: Subterranean sandstone seam + circular red danger zone & erupting sandstone/quartz spires under Ellie
## 4) `CRYSTAL_BLADE`: Close-range glowing 36 px Sun-Quartz crystal arm-sword slash + crystalline `QuartzHealthBar`
## Run: godot --rendering-driver opengl3 --path . res://tools/preview_quartz_golem.tscn -- --dir=/abs/folder

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")


func _ready() -> void:
	_run.call_deferred()


func _shot(dir: String, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, file_name])


func _run() -> void:
	var dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
	GameCursor.visible = false
	NetworkManager.host_singleplayer()
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.opening_over = true
	add_child(world)
	await get_tree().process_frame

	var hero: Player = world._players.get_child(0) as Player
	hero.intro = null
	hero.story_lock = false
	hero.wounded = false
	hero.health.floor_value = 0.0
	hero.health.max_health = 500.0
	hero.health.current = 500.0
	var wound_border: CanvasItem = hero.find_child("WoundBorder", true, false) as CanvasItem
	if wound_border != null:
		wound_border.visible = false
		wound_border.set_process(false)
	var guide: Node = hero.get_node_or_null("OpeningGuide")
	if guide != null:
		guide.set_process(false)
		if guide is CanvasItem:
			(guide as CanvasItem).visible = false
	hero.quests.set_physics_process(false)

	var cam: Camera2D = hero.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		for c: Node in hero.get_children():
			if c is Camera2D:
				cam = c as Camera2D
				break

	# Pause automatic director spawning so our staged showcase shots are deterministic and crisp
	if world.desert_guardians != null:
		world.desert_guardians.set_process(false)

	# Find a rich, flat white ground-quartz outcrop (zero cliff relief jumps!) from DesertGuardians
	var spot: Vector2 = Vector2(842.0, 185.0) * 16.0
	if world.desert_guardians != null:
		var best_score: int = -1
		for h: Dictionary in world.desert_guardians.all_homes():
			var p: Vector2 = h["pos"] as Vector2
			var base_lvl: float = Terrain.relief.level_at(p) if Terrain.relief != null else 0.0
			var flat: bool = true
			var score: int = 0
			for dy: int in range(-5, 6):
				for dx: int in range(-6, 7):
					var sample_p: Vector2 = p + Vector2(float(dx) * 12.0, float(dy) * 12.0)
					if Terrain.relief != null and absf(Terrain.relief.level_at(sample_p) - base_lvl) > 0.05:
						flat = false
					if BiomeBlend.is_quartz_surface(sample_p):
						score += 1
			if flat and score > best_score:
				best_score = score
				spot = p

	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.46 ## Warm golden desert sunlight

	hero.request_teleport(spot + Vector2(-42.0, 14.0))
	for _i: int in 95:
		await get_tree().process_frame

	hero.set_physics_process(false)
	hero.velocity = Vector2.ZERO
	hero.facing = Vector2(0.88, -0.45).normalized()
	hero._sector = 0
	hero.inventory.slots[0] = {"id": "pickaxe_basic", "count": 1}
	hero.inventory.selected = 0
	hero._animate(0.0)
	if cam != null:
		cam.zoom = Vector2(1.85, 1.85)

	# --- Shot 1: Peaceful Ground-Quartz Habitat (Dormant camouflaged pile + Classic Sun-Quartz + Mesa + Prisma variants) ---
	var g_dormant: QuartzGolem = world.spawn_quartz_golem(spot + Vector2(-8.0, -16.0), PI * 0.55, 0, true) as QuartzGolem
	var g_classic: QuartzGolem = world.spawn_quartz_golem(spot + Vector2(22.0, 4.0), PI * 0.72, 0, false) as QuartzGolem
	var g_mesa: QuartzGolem = world.spawn_quartz_golem(spot + Vector2(54.0, -12.0), PI * 0.65, 1, false) as QuartzGolem
	var g_prisma: QuartzGolem = world.spawn_quartz_golem(spot + Vector2(36.0, 28.0), PI * 0.80, 2, false) as QuartzGolem
	for g_node: QuartzGolem in [g_dormant, g_classic, g_mesa, g_prisma]:
		g_node.set_physics_process(false)
	for _i: int in 14:
		await get_tree().process_frame
	await _shot(dir, "1_peaceful_and_dormant_on_quartz")

	g_dormant.queue_free()
	g_mesa.queue_free()
	g_prisma.queue_free()
	await get_tree().process_frame

	# --- Shot 2: Attack 1 — `SHARD_VOLLEY` (3 hovering shoulder spikes + 3 flying faceted QuartzShards + red arcane corridors) ---
	hero.global_position = spot + Vector2(-46.0, 12.0)
	hero.facing = Vector2(1.0, 0.0)
	hero._sector = 0
	hero._animate(0.0)
	g_classic.set_process(false)
	g_classic.global_position = spot + Vector2(38.0, 6.0)
	var aim_to_hero: Vector2 = (hero.global_position - g_classic.global_position).normalized()
	g_classic.heading = aim_to_hero.angle()
	g_classic.attack_origin = g_classic.global_position
	g_classic.attack_dir = aim_to_hero
	g_classic.state = QuartzGolem.State.SHARD_WINDUP
	g_classic._state_time = 0.58
	g_classic._recompute_shard_lengths()
	g_classic._enter_state()
	g_classic._rig.update_rig(0.0, Vector2.ZERO, aim_to_hero.angle(), true, 0.45)
	g_classic._zone.queue_redraw()
	g_classic._ground_fx.queue_redraw()
	g_classic._fx.queue_redraw()
	# Also spawn 3 live mid-flight QuartzShards to show both the telegraph corridors and the faceted crystal projectiles!
	var s_dirs: Array[Vector2] = g_classic._shard_dirs(aim_to_hero)
	var spawned_shards: Array[QuartzShard] = []
	for idx: int in 3:
		var sh: QuartzShard = world.spawn_quartz_shard(g_classic.global_position, s_dirs[idx], g_classic._rig.shard_launch_point(idx), 0, 1.0) as QuartzShard
		sh.set_physics_process(false)
		sh.travelled = 34.0 + float(idx == 1) * 8.0
		sh._age = 0.22
		sh.global_position = sh.origin + sh.direction * sh.travelled
		sh.queue_redraw()
		sh._glow.queue_redraw()
		spawned_shards.append(sh)
	for _i2: int in 4:
		await get_tree().process_frame
	await _shot(dir, "2_shard_volley_attack")
	for sh_clean: QuartzShard in spawned_shards:
		if is_instance_valid(sh_clean):
			sh_clean.queue_free()

	# --- Shot 3: Attack 2 — `SANDSTONE_SHOCK` (Subterranean ley-fissure + arcane danger seal + erupting quartz spires & light pillars under Ellie) ---
	hero.global_position = spot + Vector2(-34.0, 10.0)
	g_classic.global_position = spot + Vector2(34.0, 4.0)
	g_classic.attack_origin = g_classic.global_position
	g_classic.shock_target = hero.global_position + Vector2(10.0, 2.0)
	g_classic.attack_dir = (g_classic.shock_target - g_classic.global_position).normalized()
	g_classic.heading = g_classic.attack_dir.angle()
	g_classic.state = QuartzGolem.State.SHOCK_SLAM
	g_classic._state_time = 0.03
	g_classic._enter_state()
	g_classic._present_shock_eruption(g_classic.shock_target)
	g_classic._erupt_age = 0.14
	g_classic._rig.update_rig(0.0, Vector2.ZERO, g_classic.attack_dir.angle(), true, 0.45)
	g_classic._zone.queue_redraw()
	g_classic._ground_fx.queue_redraw()
	g_classic._fx.queue_redraw()
	for _i3: int in 4:
		await get_tree().process_frame
	await _shot(dir, "3_sandstone_shock_eruption")

	# --- Shot 4: Attack 3 — `CRYSTAL_BLADE` (Fast close-range 40 px Sun-Quartz Greatblade slash + arcane crescent cleave fan + QuartzHealthBar) ---
	g_classic._erupt_age = -1.0
	hero.global_position = spot + Vector2(-22.0, 12.0)
	g_classic.global_position = spot + Vector2(20.0, 4.0)
	g_classic.attack_origin = g_classic.global_position
	g_classic.attack_dir = (hero.global_position - g_classic.global_position).normalized()
	g_classic.heading = g_classic.attack_dir.angle()
	var g_hp: HealthComponent = g_classic.get_node("HealthComponent") as HealthComponent
	g_hp.take_damage(14.0, hero.global_position, 0.0, hero.name.to_int())
	g_classic._rig._flash = 0.0
	for child_n: Node in world.get_children():
		if child_n is DamageNumber:
			child_n.queue_free()
	g_classic.state = QuartzGolem.State.BLADE_SLASH
	g_classic._state_time = 0.05
	g_classic._enter_state()
	g_classic.set_process(false)
	g_classic._rig.update_rig(0.0, Vector2.ZERO, g_classic.attack_dir.angle(), true, 0.45)
	g_classic._zone.queue_redraw()
	g_classic._ground_fx.queue_redraw()
	g_classic._fx.queue_redraw()
	for _i4: int in 4:
		await get_tree().process_frame
	await _shot(dir, "4_crystal_blade_close_slash")

	print("QUARTZ GOLEM PREVIEW OK")
	get_tree().quit(0)
