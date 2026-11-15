extends Node2D
## Showcase & interactive visual workbench for `AurelithRig` in the desert basin (`Tile (626, 69)`).
## - Batch Mode (`-- --dir=<path>`): clears clutter, renders 6 crisp PNGs cleanly, and exits.
## - Interactive Mode (no `--dir=`): keeps a live playable window open where Ellie can walk around
##   Aurelith and test `[1]` Dormant, `[Space]` Awaken, `[2..4]` Stages 1-3, `[5]` Attacks & `[N]` Day/Night.

const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")
const AURELITH_RIG_SCENE: PackedScene = preload("res://src/entities/enemies/desert_boss/aurelith_rig.tscn")
const SPOT: Vector2 = Vector2(626.0 * 16.0 + 8.0, 69.0 * 16.0 + 8.0)

var _interactive: bool = false
var _world: WorldLevel
var _hero: Player
var _live_rig: AurelithRig
var _live_light: NightLight
var _status_label: Label
var _live_stage: int = 1
var _attack_idx: int = 0
var _is_night: bool = false
var _detached_demo: bool = false


func _ready() -> void:
	call_deferred("_run")


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


func _spawn_rig(parent: Node2D, pos: Vector2) -> AurelithRig:
	var rig: AurelithRig = AURELITH_RIG_SCENE.instantiate() as AurelithRig
	rig.position = pos
	parent.add_child(rig)
	return rig


func _spawn_golem(world: WorldLevel, pos: Vector2, heading_rad: float = PI * 0.5, variant: int = 0) -> Node2D:
	var golem: Node2D = world.spawn_quartz_golem(pos, heading_rad, variant, false)
	if is_instance_valid(golem):
		golem.set_physics_process(false)
		golem.set_process(false)
		var rig: Node = golem.get_node_or_null("Rig")
		if rig != null and rig.has_method("update_rig"):
			rig.call("update_rig", 0.016, Vector2.ZERO, heading_rad, false)
	return golem


func _attach_light(parent: Node2D, offset: Vector2, radius: int, color: Color, energy: float) -> NightLight:
	var light: NightLight = NightLight.new()
	light.position = offset
	light.radius = radius
	light.squash = 0.72
	light.glow_color = color
	light.base_energy = energy
	parent.add_child(light)
	return light


func _clear_nodes(nodes: Array[Node]) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()


func _advance_rigs(rigs: Array[AurelithRig], steps: int = 2) -> void:
	for _s: int in steps:
		for r: AurelithRig in rigs:
			if is_instance_valid(r):
				r.queue_redraw_all()
		await get_tree().process_frame


func _suppress_player_status_and_ui(world: WorldLevel, hero: Player, hide_all_hud: bool) -> void:
	if is_instance_valid(hero):
		hero.set("intro", null)
		hero.set("story_lock", false)
		hero.set("wounded", false)
		hero.set("heat_amount", 0.0)
		var health_comp: Object = hero.get("health") as Object
		if health_comp != null:
			health_comp.set("floor_value", 0.0)
			health_comp.set("max_health", 500.0)
			health_comp.set("current", 500.0)
		var fx_comp: Object = hero.get("effects") as Object
		if fx_comp != null and fx_comp.has_method("clear"):
			fx_comp.call("clear", "sun_heat")
		var wb: CanvasItem = hero.find_child("WoundBorder", true, false) as CanvasItem
		if wb != null:
			wb.visible = false
			wb.set_process(false)
		var guide: Node = hero.get_node_or_null("OpeningGuide")
		if guide != null:
			guide.set_process(false)
			if guide is CanvasItem:
				(guide as CanvasItem).visible = false
		if hide_all_hud:
			for c: Node in hero.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
	if hide_all_hud:
		for wc: Node in world.get_children():
			if wc is CanvasLayer:
				(wc as CanvasLayer).visible = false
		for rc: Node in get_tree().root.get_children():
			if rc is CanvasLayer:
				(rc as CanvasLayer).visible = false


func _clear_basin_clutter(world: WorldLevel) -> void:
	var enemies_node: Node2D = world.get_node_or_null("Enemies") as Node2D
	if enemies_node != null:
		for child: Node in enemies_node.get_children():
			child.queue_free()
	var props_node: Node2D = world.get_node_or_null("Props") as Node2D
	if props_node != null:
		for p: Node in props_node.get_children():
			if p is Node2D and (p as Node2D).global_position.distance_to(SPOT) < 250.0:
				p.queue_free()


func _pause_spawners(world: WorldLevel) -> void:
	if world.aurelith_arena != null:
		world.aurelith_arena.set_preview_hidden(true)
	if world.desert_guardians != null:
		world.desert_guardians.set_process(false)
		world.desert_guardians.set_physics_process(false)
	if world.night != null:
		world.night.set_process(false)
		world.night.set_physics_process(false)


func _run() -> void:
	var out_dir: String = _parse_dir()
	var batch_mode: bool = not out_dir.is_empty()
	if batch_mode:
		GameCursor.visible = false
	NetworkManager.host_singleplayer()

	var world: WorldLevel = WORLD_SCENE.instantiate() as WorldLevel
	world.opening_over = true
	add_child(world)
	_world = world
	await get_tree().process_frame

	_pause_spawners(world)
	var players_node: Node2D = world.get_node("Players") as Node2D
	var enemies_node: Node2D = world.get_node("Enemies") as Node2D
	var hero: Player = players_node.get_child(0) as Player
	_hero = hero
	if hero != null:
		if hero.get("quests") != null:
			(hero.get("quests") as Node).set_physics_process(false)
		_suppress_player_status_and_ui(world, hero, batch_mode)
		hero.request_teleport(SPOT + Vector2(-94.0, 14.0))

	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.46

	# Stream chunks cleanly while keeping guardians, wild enemies & midday heat off
	for _i: int in 95:
		_pause_spawners(world)
		if hero != null:
			hero.set("heat_amount", 0.0)
		await get_tree().process_frame

	_pause_spawners(world)
	_clear_basin_clutter(world)
	await get_tree().process_frame
	_suppress_player_status_and_ui(world, hero, batch_mode)

	if not batch_mode:
		_start_interactive_mode(world, enemies_node, hero)
		return

	if hero != null:
		hero.set_physics_process(false)
		hero.set("velocity", Vector2.ZERO)
		hero.set("facing", Vector2(1.0, -0.25).normalized())
		hero.set("_sector", 0)
		if hero.has_method("_animate"):
			hero.call("_animate", 0.0)
		hero.position = SPOT + Vector2(-94.0, 14.0)

	var cam: Camera2D = Camera2D.new()
	cam.position = SPOT + Vector2(0.0, -76.0)
	cam.zoom = Vector2(1.18, 1.18)
	world.add_child(cam)
	cam.make_current()

	var active: Array[Node] = []

	# 1) Scale vs Ellie & Mini-Golems + Stage 1 "Der Erste Monolith" (Day)
	var g1: Node2D = _spawn_golem(world, SPOT + Vector2(-58.0, 22.0), PI * 0.42, 0)
	var g2: Node2D = _spawn_golem(world, SPOT + Vector2(74.0, 18.0), PI * 0.62, 1)
	var b1: AurelithRig = _spawn_rig(enemies_node, SPOT)
	b1.start_pose(AurelithRig.Pose.IDLE, 1.0, 0.35)
	b1.update_rig(0.016, Vector2.ZERO, PI * 0.5)
	active = [g1, g2, b1]
	await _advance_rigs([b1])
	await _shot(out_dir, "1_scale_and_stage1_day")
	_clear_nodes(active)

	# 2) Dormant Sand-Buried Monument & Awakening Rise (Day)
	if hero != null:
		hero.position = SPOT + Vector2(-210.0, 24.0)
	cam.position = SPOT + Vector2(0.0, -68.0)
	cam.zoom = Vector2(1.06, 1.06)
	var gd1: Node2D = _spawn_golem(world, SPOT + Vector2(-156.0, 20.0), PI * 0.36, 0)
	var gd2: Node2D = _spawn_golem(world, SPOT + Vector2(-62.0, 28.0), PI * 0.66, 2)
	var b_dorm: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(-112.0, 8.0))
	b_dorm.soul_charge = 0.72
	b_dorm.start_pose(AurelithRig.Pose.DORMANT, 1.0, 0.35)
	b_dorm.update_rig(0.016, Vector2.ZERO, PI * 0.5)

	var b_wake: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(104.0, 4.0))
	b_wake.soul_charge = 1.0
	b_wake.start_pose(AurelithRig.Pose.AWAKEN, 1.0, 0.66)
	b_wake.update_rig(0.016, Vector2.ZERO, PI * 0.5)
	active = [gd1, gd2, b_dorm, b_wake]
	await _advance_rigs([b_dorm, b_wake])
	await _shot(out_dir, "2_dormant_and_awakening")
	_clear_nodes(active)

	# 3) Stage 2: Unleashed Prism — 8 Crystal Wings + Twin Greatblades + Detached Rocket Gauntlet
	TimeManager.time_of_day = 0.60
	cam.position = SPOT + Vector2(0.0, -74.0)
	cam.zoom = Vector2(0.96, 0.96)
	var b_blade: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(-120.0, 10.0))
	b_blade.prism_release = 1.0
	b_blade.soul_charge = 0.8
	b_blade.twin_blades = true
	b_blade.start_pose(AurelithRig.Pose.BLADE_CLEAVE, 1.0, 0.44)
	b_blade.update_rig(0.016, Vector2.ZERO, PI * 0.45)

	var b_slam: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(96.0, 4.0))
	b_slam.prism_release = 1.0
	b_slam.soul_charge = 0.9
	b_slam.start_pose(AurelithRig.Pose.GAUNTLET_SLAM, 1.0, 0.46)
	b_slam.set_detached_fist(true, true, SPOT + Vector2(204.0, 28.0), 22.0)
	b_slam.update_rig(0.016, Vector2.ZERO, PI * 0.55)
	active = [b_blade, b_slam]
	await _advance_rigs([b_blade, b_slam])
	await _shot(out_dir, "3_stage2_unleashed_prism")
	_clear_nodes(active)

	# 4) Stage 3: Herz der Singenden Dünen — 96px Sandstorm Funnel + Twin Armillary Rings + Overheat Stagger
	TimeManager.time_of_day = 0.48
	cam.position = SPOT + Vector2(0.0, -76.0)
	cam.zoom = Vector2(0.95, 0.95)
	var b_s3: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(-116.0, 8.0))
	b_s3.prism_release = 1.0
	b_s3.storm_ascension = 1.0
	b_s3.soul_charge = 1.0
	b_s3.twin_blades = true
	b_s3.charge_intensity = 0.78
	b_s3.start_pose(AurelithRig.Pose.ZENITH_CHARGE, 1.0, 0.55)
	b_s3.update_rig(0.016, Vector2.ZERO, PI * 0.52)

	var b_stag: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(122.0, 14.0))
	b_stag.prism_release = 1.0
	b_stag.storm_ascension = 1.0
	b_stag.soul_charge = 1.0
	b_stag.start_pose(AurelithRig.Pose.STAGGER, 1.0, 0.35)
	b_stag.update_rig(0.016, Vector2.ZERO, PI * 0.5)
	active = [b_s3, b_stag]
	await _advance_rigs([b_s3, b_stag])
	await _shot(out_dir, "4_stage3_cyclone_and_stagger")
	_clear_nodes(active)

	# 5) Night Glow Showcase (Stages 1, 2 & 3 with NightLight)
	TimeManager.time_of_day = 0.02
	if hero != null:
		hero.position = SPOT + Vector2(-282.0, 32.0)
	cam.position = SPOT + Vector2(0.0, -76.0)
	cam.zoom = Vector2(0.90, 0.90)
	var bn1: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(-188.0, 10.0))
	bn1.start_pose(AurelithRig.Pose.IDLE, 1.0, 0.25)
	bn1.update_rig(0.016, Vector2.ZERO, PI * 0.5)
	_attach_light(bn1, Vector2(0.0, -76.0), 155, Color("78f4e6"), 1.05)

	var bn2: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(0.0, -6.0))
	bn2.prism_release = 1.0
	bn2.soul_charge = 0.8
	bn2.start_pose(AurelithRig.Pose.CHEST_BEAM, 1.0, 0.55)
	bn2.update_rig(0.016, Vector2.ZERO, PI * 0.5)
	_attach_light(bn2, Vector2(0.0, -80.0), 175, Color("b47aff"), 1.15)

	var bn3: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(188.0, 10.0))
	bn3.prism_release = 1.0
	bn3.storm_ascension = 1.0
	bn3.soul_charge = 1.0
	bn3.charge_intensity = 0.85
	bn3.twin_blades = true
	bn3.start_pose(AurelithRig.Pose.ZENITH_CHARGE, 1.0, 0.65)
	bn3.update_rig(0.016, Vector2.ZERO, PI * 0.5)
	_attach_light(bn3, Vector2(0.0, -82.0), 195, Color("ff8844"), 1.25)

	var gn: Node2D = _spawn_golem(world, SPOT + Vector2(-252.0, 26.0), PI * 0.35, 0)
	active = [bn1, bn2, bn3, gn]
	for _n: int in 8:
		await get_tree().process_frame
	await _advance_rigs([bn1, bn2, bn3])
	await _shot(out_dir, "5_night_glow_showcase")
	_clear_nodes(active)

	# 6) 4-Angle Turnaround (Front, Right 3/4, Back Stage 2, Left 3/4 Stage 2 Beam)
	TimeManager.time_of_day = 0.46
	cam.position = SPOT + Vector2(0.0, -76.0)
	cam.zoom = Vector2(0.84, 0.84)
	var bt0: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(-248.0, 6.0))
	bt0.start_pose(AurelithRig.Pose.IDLE, 1.0, 0.2)
	bt0.update_rig(0.016, Vector2.ZERO, PI * 0.5)

	var bt1: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(-84.0, 6.0))
	bt1.start_pose(AurelithRig.Pose.IDLE, 1.0, 0.45)
	bt1.update_rig(0.016, Vector2.ZERO, 0.22)

	var bt2: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(84.0, 6.0))
	bt2.prism_release = 1.0
	bt2.start_pose(AurelithRig.Pose.IDLE, 1.0, 0.3)
	bt2.update_rig(0.016, Vector2.ZERO, -PI * 0.5)

	var bt3: AurelithRig = _spawn_rig(enemies_node, SPOT + Vector2(248.0, 6.0))
	bt3.prism_release = 1.0
	bt3.start_pose(AurelithRig.Pose.CHEST_BEAM, 1.0, 0.55)
	bt3.update_rig(0.016, Vector2.ZERO, PI - 0.22)

	active = [bt0, bt1, bt2, bt3]
	for _t: int in 6:
		await get_tree().process_frame
	await _advance_rigs([bt0, bt1, bt2, bt3])
	await _shot(out_dir, "6_turnaround_angles")
	_clear_nodes(active)

	print("AURELITH PREVIEW OK -> %s" % out_dir)
	get_tree().quit()


# ==============================================================================
# INTERACTIVE LIVE WINDOW MODE (WHEN LAUNCHED WITHOUT `--dir=`)
# ==============================================================================
func _start_interactive_mode(world: WorldLevel, enemies_node: Node2D, hero: Player) -> void:
	_interactive = true
	if is_instance_valid(hero):
		hero.set_physics_process(true)
		var cam: Camera2D = hero.view_camera()
		if cam != null:
			cam.zoom = Vector2(1.16, 1.16)
			cam.make_current()

	_live_rig = _spawn_rig(enemies_node, SPOT)
	_live_light = _attach_light(_live_rig, Vector2(0.0, -78.0), 175, Color("78f4e6"), 1.1)
	_spawn_golem(world, SPOT + Vector2(-118.0, 34.0), PI * 0.32, 0)
	_spawn_golem(world, SPOT + Vector2(114.0, 26.0), PI * 0.68, 1)
	_spawn_golem(world, SPOT + Vector2(-84.0, -56.0), PI * 0.45, 2)

	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	panel.add_child(_status_label)

	_apply_live_stage(1)


func _apply_live_stage(stage: int) -> void:
	_live_stage = stage
	_detached_demo = false
	_live_rig.set_detached_fist(true, false)
	_live_rig.set_detached_fist(false, false)
	match stage:
		0:
			_live_rig.prism_release = 0.0
			_live_rig.storm_ascension = 0.0
			_live_rig.soul_charge = 0.72
			_live_rig.twin_blades = false
			_live_rig.charge_intensity = 0.0
			_live_rig.start_pose(AurelithRig.Pose.DORMANT, 1.0, 0.0)
			if is_instance_valid(_live_light):
				_live_light.glow_color = Color("78f4e6")
		1:
			_live_rig.prism_release = 0.0
			_live_rig.storm_ascension = 0.0
			_live_rig.soul_charge = 0.5
			_live_rig.twin_blades = false
			_live_rig.charge_intensity = 0.0
			_live_rig.start_pose(AurelithRig.Pose.IDLE, 1.0, 0.0)
			if is_instance_valid(_live_light):
				_live_light.glow_color = Color("78f4e6")
		2:
			_live_rig.prism_release = 1.0
			_live_rig.storm_ascension = 0.0
			_live_rig.soul_charge = 0.85
			_live_rig.twin_blades = true
			_live_rig.charge_intensity = 0.35
			_live_rig.start_pose(AurelithRig.Pose.IDLE, 1.0, 0.0)
			if is_instance_valid(_live_light):
				_live_light.glow_color = Color("b47aff")
		3:
			_live_rig.prism_release = 1.0
			_live_rig.storm_ascension = 1.0
			_live_rig.soul_charge = 1.0
			_live_rig.twin_blades = true
			_live_rig.charge_intensity = 0.65
			_live_rig.start_pose(AurelithRig.Pose.IDLE, 1.0, 0.0)
			if is_instance_valid(_live_light):
				_live_light.glow_color = Color("ff8844")
	_refresh_overlay_text("IDLE")


func _refresh_overlay_text(pose_name: String) -> void:
	if _status_label == null:
		return
	var stage_names: Array[String] = ["Dormant Monument", "Stage 1: Der Erste Monolith", "Stage 2: Entfesseltes Prisma", "Stage 3: Singende Dünen"]
	var dn: String = "Nacht" if _is_night else "Tag"
	_status_label.text = "AURELITH PREVIEW | %s | Pose: %s | Zeit: %s\n[1] Dormant  [Space] Awaken  [2] Stage 1  [3] Stage 2  [4] Stage 3  [5] Attack  [N] Tag/Nacht" % [
		stage_names[_live_stage], pose_name, dn,
	]


func _unhandled_input(event: InputEvent) -> void:
	if not _interactive or not (event is InputEventKey):
		return
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	match ke.keycode:
		KEY_1:
			_apply_live_stage(0)
		KEY_2:
			_apply_live_stage(1)
		KEY_3:
			_apply_live_stage(2)
		KEY_4:
			_apply_live_stage(3)
		KEY_SPACE:
			if _live_stage == 0:
				_live_stage = 1
			_detached_demo = false
			_live_rig.set_detached_fist(true, false)
			_live_rig.start_pose(AurelithRig.Pose.AWAKEN, 1.8, 0.0)
			_refresh_overlay_text("AWAKEN")
		KEY_N:
			_is_night = not _is_night
			TimeManager.time_of_day = 0.02 if _is_night else 0.46
			_refresh_overlay_text("LIVE")
		KEY_5:
			if _live_stage == 0:
				_apply_live_stage(1)
			var poses: Array[AurelithRig.Pose] = [
				AurelithRig.Pose.GAUNTLET_SLAM,
				AurelithRig.Pose.FAULT_SLAM,
				AurelithRig.Pose.BLADE_CLEAVE,
				AurelithRig.Pose.CHEST_BEAM,
				AurelithRig.Pose.CLAP_CRUSH,
				AurelithRig.Pose.ZENITH_CHARGE,
				AurelithRig.Pose.STAGGER,
			]
			var p_names: Array[String] = ["GAUNTLET_SLAM (Detached)", "FAULT_SLAM", "BLADE_CLEAVE", "CHEST_BEAM", "CLAP_CRUSH", "ZENITH_CHARGE", "STAGGER"]
			var cur: AurelithRig.Pose = poses[_attack_idx]
			_detached_demo = (cur == AurelithRig.Pose.GAUNTLET_SLAM)
			_live_rig.set_detached_fist(true, false)
			_live_rig.start_pose(cur, 2.2, 0.0)
			_refresh_overlay_text(p_names[_attack_idx])
			_attack_idx = (_attack_idx + 1) % poses.size()


func _process(delta: float) -> void:
	if not _interactive or not is_instance_valid(_live_rig):
		return
	if is_instance_valid(_hero):
		_hero.set("heat_amount", 0.0)
		var cam: Camera2D = _hero.view_camera()
		if cam != null:
			cam.zoom = Vector2(1.16, 1.16)
		var aim: float = (_hero.global_position - _live_rig.global_position).angle()
		if _detached_demo and is_instance_valid(_hero):
			_live_rig.set_detached_fist(true, true, _hero.global_position + Vector2(28.0, -6.0), 18.0 + sin(Time.get_ticks_msec() * 0.006) * 10.0)
		_live_rig.update_rig(delta, Vector2.ZERO, aim)
	else:
		_live_rig.update_rig(delta, Vector2.ZERO, PI * 0.5)
