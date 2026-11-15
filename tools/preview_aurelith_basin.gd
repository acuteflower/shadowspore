extends Node2D
## Visual verification capture for Paket 2 (`AurelithArena` at `Tile 626, 69`):
## Captures 3 live OpenGL3 screenshots of the real Singing Basin in `WorldLevel`:
## 1) `1_basin_dormant_6_sentinels.png`: Wide view of the 6 radial quartz star-veins, 6 QuartzGolems & dormant monument.
## 2) `2_basin_soul_drain_escalation.png`: 4/6 sentinels slain — lit solar-ley veins, floating pebbles & soul ribbon.
## 3) `3_basin_sealed_storm_ring.png`: Awakened Aurelith hovering inside the erupted 36-tooth sintered-quartz & sandstorm ring!

const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")


func _ready() -> void:
	_run.call_deferred()


func _parse_dir() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			return a.substr(6)
	return ""


func _shot(dir: String, file_name: String) -> void:
	for _f: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, file_name])


func _wait_sec(sec: float) -> void:
	var t: float = 0.0
	while t < sec:
		await get_tree().physics_frame
		await get_tree().process_frame
		t += get_physics_process_delta_time()


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
	hero.health.max_health = 5000.0
	hero.health.current = 5000.0
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
	cam.zoom = Vector2(0.88, 0.88)
	add_child(cam)

	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.54
	hero.request_teleport(spot + Vector2(0.0, 146.0))
	await _wait_sec(0.9)

	# Freeze sentinel wandering briefly for crisp shot 1
	for g: Node2D in arena._guardians:
		if is_instance_valid(g):
			g.set_physics_process(false)
	await _shot(out_dir, "1_basin_dormant_6_sentinels")

	# Shot 2: Slay 4 sentinels + trigger active soul stream + twilight glow
	TimeManager.time_of_day = 0.75
	for idx: int in 4:
		var g_node: Node2D = arena._guardians[idx]
		if g_node != null and is_instance_valid(g_node):
			var hb: HurtboxComponent = g_node.get_node("Hurtbox") as HurtboxComponent
			hb.take_hit(999.0, hero.global_position, 30.0, hero.name.to_int())
	arena._display_charge = 0.68
	await _wait_sec(0.28)
	# Clear debug 999 DamageNumber popups so the screenshot reads as pure atmospheric ingame art
	for child: Node in world.get_children():
		if child is DamageNumber:
			child.queue_free()
	for child2: Node in get_children():
		if child2 is DamageNumber:
			child2.queue_free()
	await _shot(out_dir, "2_basin_soul_drain_escalation")

	# Shot 3: Trigger full awakening & sealed 44-tooth sintered-quartz storm wall (full 360 ring view)!
	TimeManager.time_of_day = 0.58
	cam.position = spot + Vector2(0.0, -18.0)
	cam.zoom = Vector2(0.73, 0.73)
	arena.debug_fight()
	# Skip BossIntro bars for clean arena-wide capture
	for rc: Node in get_tree().root.get_children():
		if rc.name == "BossIntroLayer":
			rc.queue_free()
	if arena.boss != null:
		arena.boss._intro = null
	await _wait_sec(3.1)
	for rc2: Node in get_tree().root.get_children():
		if rc2.name == "BossIntroLayer":
			rc2.queue_free()
	await _shot(out_dir, "3_basin_sealed_storm_ring")

	print("AURELITH BASIN PREVIEW OK")
	get_tree().quit(0)
