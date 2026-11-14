extends Node
## OpenGL3 visual preview capture for Die Zenitwarte across all 5 exterior zones (day, noon, night, shaders).
## Run: godot --rendering-driver opengl3 --path . res://tools/preview_desert_observatory.tscn -- --out=/abs/dir

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

var _world: WorldLevel
var _hero: Player
var _cam: Camera2D
var _obs: DesertObservatory


func _ready() -> void:
	_run.call_deferred()


func _shot(out_dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	if not out_dir.is_empty():
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))


func _focus_and_settle(pos: Vector2, zoom_val: float, tod: float, frames: int = 90) -> void:
	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = tod
	if _hero != null:
		_hero.set_physics_process(true)
		_hero.cool_down(60.0)
		_hero.request_teleport(pos)
	if _cam != null:
		_cam.zoom = Vector2(zoom_val, zoom_val)
	for _i: int in frames:
		await get_tree().process_frame


func _run() -> void:
	var out_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--dir="):
			out_dir = arg.trim_prefix("--dir=")

	GameCursor.visible = false
	_world = WORLD.instantiate() as WorldLevel
	if _world == null:
		push_error("PREVIEW: world_level.tscn failed to instantiate")
		get_tree().quit(1)
		return
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_world.finish_opening()

	_obs = _world.desert_observatory
	_hero = _world._players.get_child(0) as Player
	if _hero != null:
		var og: Node = _hero.get_node_or_null("OpeningGuide")
		if og != null:
			og.set_process(false)
		if _hero.quests != null:
			_hero.quests.set_physics_process(false)
		for ch: Node in _hero.get_children():
			if ch is Camera2D:
				_cam = ch as Camera2D
				break
	var hud: CanvasLayer = _world.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	for child: Node in _world.get_children():
		var cl: CanvasLayer = child as CanvasLayer
		if cl != null and cl.name != "MoodGrade":
			cl.visible = false

	# 1. Summit Rotunda + Armillary + Telescope Lenses + Ellie standing on upper Star-Portal stairs at Zenith Noon
	await _focus_and_settle(_obs._rotunda_pos + Vector2(0.0, 18.0), 1.05, 0.50, 100)
	_obs._surge_timer = 3.0
	for _i: int in 8:
		await get_tree().process_frame
	await _shot(out_dir, "obs_1_rotunda_day_noon")

	# 2. Summit Rotunda at Night (Ghost-Dome Wireframe, Starlight Beam, Glowing Star-Locks & Runes)
	await _focus_and_settle(_obs._rotunda_pos + Vector2(44.0, 48.0), 0.92, 0.0, 75)
	_obs.on_arcane_lightning(_obs._rotunda_pos)
	if is_instance_valid(_obs._portal_locks_fx):
		_obs._portal_locks_fx.flare(3.5)
	for _i: int in 14:
		await get_tree().process_frame
	await _shot(out_dir, "obs_2_rotunda_night_beam")

	# 3. East Bastion 180° Sundial & Gnomon casting real-time shadow (crisp morning angle)
	await _focus_and_settle(_obs._sundial_pos + Vector2(72.0, 26.0), 1.28, 0.36, 85)
	_obs._process(0.05)
	for _i: int in 6:
		await get_tree().process_frame
	await _shot(out_dir, "obs_3_sundial_and_gnomon")

	# 4. West Terrace Sunken Star-Mirror Basin (Void-nebula & Constellations) + Polar Ocular
	var terrace_mid: Vector2 = (_obs._mirror_pos + _obs._ocular_pos) * 0.5 + Vector2(0.0, 20.0)
	await _focus_and_settle(terrace_mid, 1.04, 0.0, 85)
	_obs._process(0.05)
	for _i: int in 10:
		await get_tree().process_frame
	await _shot(out_dir, "obs_4_star_mirror_and_ocular")

	# 5. Arrival from Northern Caravan Road at Split Ecliptic Gate + Wind-Harp Causeway
	await _focus_and_settle(_obs._gate_pos + Vector2(0.0, 28.0), 1.08, 0.34, 85)
	_obs._trigger_all_conduits()
	for _i: int in 12:
		await get_tree().process_frame
	await _shot(out_dir, "obs_5_ecliptic_gate_arrival")

	# 6. Causeway L1 -> L2 -> L3 flush meridian conduits & relocated Wind-Harp pillars
	await _focus_and_settle(Vector2(936.0 * 16.0, 164.0 * 16.0), 0.92, 0.42, 85)
	_obs._trigger_all_conduits()
	for _i: int in 14:
		await get_tree().process_frame
	await _shot(out_dir, "obs_6_causeway_meridian_rails")

	TimeManager.unlock()
	get_tree().quit(0)
