extends Node
## Live OpenGL3 visual verification of:
## 1) `ShadowSpider` (Void-web fan + barbed grapple snare) & `VoidListener` (echolocation scream + acoustic resonance lane)
## 2) `VoidCrusher` (tectonic fault-slam + spinning Void-scythe vortex) & `LightFisher` (angler-fang jaw snap + Void whirlpool discs)
## 3) Void Boss `FeatherField` (`feather_zones.gdshader` + `_draw_cage`) on Mornath's real arena flagstones
## 4) `ERHITZT` (`sun_heat`) Desert Heat-Mirage HUD effect (`HeatHaze` on `CanvasLayer 0`, wavering world air under crisp HUD vines)
## Run: godot --rendering-driver opengl3 --path . res://tools/preview_void_and_heat.tscn -- --dir=/abs/folder

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
const SPIDER_SCENE: PackedScene = preload("res://src/entities/enemies/shadow_spider.tscn")
const LISTENER_SCENE: PackedScene = preload("res://src/entities/enemies/void_listener.tscn")
const CRUSHER_SCENE: PackedScene = preload("res://src/entities/enemies/void_crusher.tscn")
const FISHER_SCENE: PackedScene = preload("res://src/entities/enemies/light_fisher.tscn")


func _ready() -> void:
	_run.call_deferred()


func _shot(dir: String, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, file_name])


func _find_heat_haze(hero: Player) -> HeatHaze:
	var hud: CanvasLayer = hero.get("_hud") as CanvasLayer
	if hud == null:
		return null
	return hud.find_child("HeatHaze", true, false) as HeatHaze


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
	if hero.quests != null:
		hero.quests.set_flag("hud_unlocked")
		hero.quests.set_physics_process(false)

	var cam: Camera2D = hero.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.zoom = Vector2(1.75, 1.75)

	# --- Shot 1: ShadowSpider (Void-Web Bite Fan + Grapple Snare) & VoidListener (Echolocation Scream + Resonance Wave) ---
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.88 ## Atmospheric twilight-night so Void rifts glow vividly on meadow grass
	var meadow_spot: Vector2 = world._spawn_position(0) + Vector2(0.0, 28.0)
	hero.request_teleport(meadow_spot)
	for _w0: int in 75:
		await get_tree().process_frame
	hero.set_physics_process(false)
	hero.velocity = Vector2.ZERO
	var hud_node: CanvasLayer = hero.get("_hud") as CanvasLayer
	if hud_node != null:
		hud_node.visible = false

	var spider_fan: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	spider_fan.name = "PreviewSpiderFan"
	spider_fan.position = meadow_spot + Vector2(-78.0, -24.0)
	world.get_node("Enemies").add_child(spider_fan)
	spider_fan.set_physics_process(false)
	spider_fan.set_process(false)
	spider_fan.state = ShadowSpider.State.WINDUP
	spider_fan._state_msec = Time.get_ticks_msec() - 420
	spider_fan.attack_origin = spider_fan.global_position
	spider_fan.attack_dir = Vector2(0.92, 0.38).normalized()
	spider_fan._enter_state()
	spider_fan._rig.update_rig(0.3, Vector2.ZERO, spider_fan.attack_dir.angle())
	spider_fan._zone.queue_redraw()

	var spider_grap: ShadowSpider = SPIDER_SCENE.instantiate() as ShadowSpider
	spider_grap.name = "PreviewSpiderGrap"
	spider_grap.position = meadow_spot + Vector2(-82.0, 26.0)
	world.get_node("Enemies").add_child(spider_grap)
	spider_grap.set_physics_process(false)
	spider_grap.set_process(false)
	spider_grap.state = ShadowSpider.State.GRAPPLE_WINDUP
	spider_grap._state_msec = Time.get_ticks_msec() - 520
	spider_grap.anchor = meadow_spot + Vector2(-24.0, 30.0)
	spider_grap.attack_dir = (spider_grap.anchor - spider_grap.global_position).normalized()
	spider_grap._enter_state()
	spider_grap._rig.update_rig(0.3, Vector2.ZERO, spider_grap.attack_dir.angle())
	spider_grap._zone.queue_redraw()

	var listener_scream: VoidListener = LISTENER_SCENE.instantiate() as VoidListener
	listener_scream.name = "PreviewListenerScream"
	listener_scream.position = meadow_spot + Vector2(36.0, -24.0)
	world.get_node("Enemies").add_child(listener_scream)
	listener_scream.set_physics_process(false)
	listener_scream.set_process(false)
	listener_scream.state = VoidListener.State.SCREAM_WINDUP
	listener_scream._state_time = 0.52
	listener_scream.attack_origin = listener_scream.global_position
	listener_scream.attack_dir = Vector2(-0.92, 0.35).normalized()
	listener_scream._enter_state()
	listener_scream._rig.update_rig(0.3, Vector2.ZERO, listener_scream.attack_dir.angle())
	listener_scream._zone.queue_redraw()

	var listener_wave: VoidListener = LISTENER_SCENE.instantiate() as VoidListener
	listener_wave.name = "PreviewListenerWave"
	listener_wave.position = meadow_spot + Vector2(82.0, 26.0)
	world.get_node("Enemies").add_child(listener_wave)
	listener_wave.set_physics_process(false)
	listener_wave.set_process(false)
	listener_wave.state = VoidListener.State.WAVE_WINDUP
	listener_wave._state_time = 0.62
	listener_wave.warning_length = 74.0
	listener_wave.attack_origin = listener_wave.global_position
	listener_wave.attack_dir = Vector2(-1.0, 0.0)
	listener_wave._enter_state()
	listener_wave._rig.update_rig(0.3, Vector2.ZERO, listener_wave.attack_dir.angle())
	listener_wave._zone.queue_redraw()

	for _f1: int in 5:
		await get_tree().process_frame
	await _shot(dir, "void_1_spider_and_listener")

	for n1: Node in [spider_fan, spider_grap, listener_scream, listener_wave]:
		n1.queue_free()
	await get_tree().process_frame

	# --- Shot 2: VoidCrusher (Tectonic Slam + Scythe Sweep + Bull-Rush) & LightFisher (Angler-Fang Jaw + Void Whirlpool) ---
	var crusher_slam: VoidCrusher = CRUSHER_SCENE.instantiate() as VoidCrusher
	crusher_slam.name = "PreviewCrusherSlam"
	crusher_slam.position = meadow_spot + Vector2(-72.0, -18.0)
	world.get_node("Enemies").add_child(crusher_slam)
	crusher_slam.set_physics_process(false)
	crusher_slam.set_process(false)
	crusher_slam.get_node("HealthBar").hide()
	crusher_slam.state = VoidCrusher.State.SLAM_WINDUP
	crusher_slam._state_time = 0.72
	crusher_slam.attack_origin = crusher_slam.global_position
	crusher_slam.attack_dir = Vector2(0.95, 0.25).normalized()
	crusher_slam._enter_state()
	crusher_slam._rig.update_rig(0.3, Vector2.ZERO, crusher_slam.attack_dir.angle(), crusher_slam.attack_dir.angle())
	crusher_slam._zone.queue_redraw()

	var crusher_rush: VoidCrusher = CRUSHER_SCENE.instantiate() as VoidCrusher
	crusher_rush.name = "PreviewCrusherRush"
	crusher_rush.position = meadow_spot + Vector2(-84.0, 34.0)
	world.get_node("Enemies").add_child(crusher_rush)
	crusher_rush.set_physics_process(false)
	crusher_rush.set_process(false)
	crusher_rush.get_node("HealthBar").hide()
	crusher_rush.state = VoidCrusher.State.RUSH_WINDUP
	crusher_rush._state_time = 0.76
	crusher_rush.warning_length = 72.0
	crusher_rush.attack_origin = crusher_rush.global_position
	crusher_rush.attack_dir = Vector2(1.0, 0.0)
	crusher_rush._enter_state()
	crusher_rush._rig.update_rig(0.3, Vector2.ZERO, crusher_rush.attack_dir.angle(), crusher_rush.attack_dir.angle())
	crusher_rush._zone.queue_redraw()

	var fisher_snap: LightFisher = FISHER_SCENE.instantiate() as LightFisher
	fisher_snap.name = "PreviewFisherSnap"
	fisher_snap.position = meadow_spot + Vector2(68.0, -18.0)
	world.get_node("Enemies").add_child(fisher_snap)
	fisher_snap.set_physics_process(false)
	fisher_snap.set_process(false)
	fisher_snap.get_node("HealthBar").hide()
	fisher_snap.state = LightFisher.State.SNAP_WINDUP
	fisher_snap._state_time = 0.56
	fisher_snap.attack_origin = fisher_snap.global_position
	fisher_snap.attack_dir = Vector2(-0.96, 0.25).normalized()
	fisher_snap._rig.start_pose(FisherRig.Pose.SNAP_WINDUP, 0.7, 0.56)
	fisher_snap._rig.update_rig(0.1, Vector2.ZERO, fisher_snap.attack_dir.angle(), Vector2(-20.0, 4.0), 1.0, 1.0, true)
	fisher_snap._zone.queue_redraw()

	var fisher_orbs: LightFisher = FISHER_SCENE.instantiate() as LightFisher
	fisher_orbs.name = "PreviewFisherOrbs"
	fisher_orbs.position = meadow_spot + Vector2(78.0, 28.0)
	world.get_node("Enemies").add_child(fisher_orbs)
	fisher_orbs.set_physics_process(false)
	fisher_orbs.set_process(false)
	fisher_orbs.get_node("HealthBar").hide()
	fisher_orbs.state = LightFisher.State.ORB_CAST
	fisher_orbs._state_time = 1.55
	fisher_orbs._burst_done = [false, false, false]
	fisher_orbs._burst_heard = [false, false, false]
	fisher_orbs.aim_points = PackedVector2Array([meadow_spot + Vector2(24.0, 26.0), meadow_spot + Vector2(48.0, 42.0)])
	fisher_orbs._rig.start_pose(FisherRig.Pose.ORB_CAST, 2.4, 1.55)
	fisher_orbs._rig.update_rig(0.1, Vector2.ZERO, PI, Vector2(-22.0, 0.0), 1.0, 1.0, true)
	fisher_orbs._zone.queue_redraw()

	for _f2: int in 5:
		await get_tree().process_frame
	await _shot(dir, "void_2_crusher_and_fisher")

	for n2: Node in [crusher_slam, crusher_rush, fisher_snap, fisher_orbs]:
		n2.queue_free()
	await get_tree().process_frame

	# --- Shot 3: Void Boss Arena (`FeatherField` / `feather_zones.gdshader` + `_draw_cage`) on Mornath's real arena flagstones ---
	var arena_decal: Dictionary = {}
	for dec: Dictionary in DataRegistry.table("ground_baked").get("decals", []) as Array:
		if String(dec.get("id", "")).ends_with("_arena"):
			arena_decal = dec
			break
	if not arena_decal.is_empty():
		var arena_center: Vector2 = Vector2(float(arena_decal["x"]) + 144.0, float(arena_decal["y"]) + 180.0)
		hero.global_position = arena_center + Vector2(-12.0, 8.0)
		for _w_ar: int in 55:
			await get_tree().process_frame
		var field: FeatherField = FeatherField.new()
		world.add_child(field)
		field.setup(arena_decal, true)
		var now_t: float = field.now()
		# Threat lane (slash beam warning), Threat disc, Threat ring, Lingering Void infection, and Closing Feather-Snare Cage!
		field.add_lane(arena_center + Vector2(-95.0, -38.0), arena_center + Vector2(88.0, -16.0), 13.0, now_t, now_t + 0.9, 0.0, 60.0, 0)
		field.add_ring(arena_center + Vector2(-46.0, 26.0), 28.0, 0.0, now_t, now_t + 0.85, 0.0, 60.0, 0)
		field.add_ring(arena_center + Vector2(44.0, 24.0), 34.0, 16.0, now_t, now_t + 0.85, 0.0, 60.0, 0)
		field.add_ring(arena_center + Vector2(0.0, -6.0), 18.0, 0.0, now_t, now_t + 1.2, 0.0, 60.0, 1)
		field.add_cage(arena_center + Vector2(0.0, 4.0), 68.0, 28.0, -PI * 0.25, 0.72, now_t, now_t + 1.4, now_t + 2.8, 0.0, 60.0, 8.0)
		for _f3: int in 26:
			await get_tree().process_frame
		await _shot(dir, "void_3_boss_arena_zones")
		field.queue_free()

	# --- Shot 4: `ERHITZT` Desert Midday Heat-Mirage HUD Effect (`HeatHaze` on `CanvasLayer 0` + crisp HUD vines) ---
	TimeManager.time_of_day = 0.48 ## Scorching high noon in Sonnenquarz-Öde!
	var desert_spot: Vector2 = Vector2(835.0, 188.0) * 16.0
	if world.desert_guardians != null and not world.desert_guardians.all_homes().is_empty():
		desert_spot = (world.desert_guardians.all_homes()[0] as Dictionary)["pos"] as Vector2
	hero.request_teleport(desert_spot)
	for _w_des: int in 90:
		await get_tree().process_frame
	if cam != null:
		cam.zoom = Vector2(1.0, 1.0) ## Real 640x360 gameplay HUD view!
	if hud_node != null:
		hud_node.visible = true
		hud_node.open()
	hero.heat_amount = 0.95
	if hero.effects != null:
		hero.effects.apply("sun_heat", 8.0, 0.95)
	var haze: HeatHaze = _find_heat_haze(hero)
	if haze != null:
		haze.set_preview_amount(0.95)
	for _f4: int in 35:
		await get_tree().process_frame
	await _shot(dir, "heat_4_desert_mirage_erhitzt")

	print("VOID ZONES AND HEAT PREVIEW OK")
	get_tree().quit(0)
