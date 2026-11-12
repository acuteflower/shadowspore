extends Node2D
## Look study of the crow's hoard (docs/raetsel_konzept.md 4): the snag with its crow and glitter, the crow on the ground, in flight, scratching at
## the mound, and a chest breaking out of the earth. Offline, no world, no save; the states are set by hand.
##   Godot --rendering-driver opengl3 --path . tools/preview_crow_hoard.tscn -- --dir=/abs/folder [--night]

var _dir: String = ""
var _night: bool = false
var _raven: bool = false
var _hoard: CrowHoard
var _chests: LootChests
var _cam: Camera2D


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.substr(6)
		elif arg == "--night":
			_night = true
		elif arg == "--raven":
			_raven = true
	var ground: ColorRect = ColorRect.new()
	ground.color = Color("3a5a3c") if not _night else Color("1b2a26")
	ground.size = Vector2(4000, 3000)
	ground.position = Vector2(-2000, -1500)
	ground.z_index = -20
	add_child(ground)
	if _night:
		var dark: CanvasModulate = CanvasModulate.new()
		dark.color = Color(0.3, 0.3, 0.46)
		add_child(dark)
	_chests = LootChests.new()
	add_child(_chests)
	_hoard = CrowHoard.new()
	if _raven:
		_hoard.setup({"id": "preview_raven", "kind": "raven_trade", "tier": "rare", "tile": [0, 0], "variant": 0, "stations": [[4, 3]], "mound": [9, 2]}, DataRegistry.table("puzzles").get("raven", {}) as Dictionary)
	else:
		_hoard.setup({"id": "preview_hoard", "kind": "crow_hoard", "tier": "common", "tile": [0, 0], "mound": [9, 2]}, DataRegistry.table("puzzles").get("crow", {}) as Dictionary)
	_hoard.manual = true
	add_child(_hoard)
	_hoard.set_night(1.0 if _night else 0.0)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(3, 3)
	add_child(_cam)
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	if _dir != "":
		get_viewport().get_texture().get_image().save_png(_dir.path_join("crow_%s%s.png" % [name, "_night" if _night else ""]))


func _run_raven() -> void:
	var snag: Vector2 = _hoard.snag_position()
	_cam.position = snag + Vector2(0, -16)
	await _wait(0.6)
	await _snap("raven_1_perch")
	_hoard._start_flight(CrowHoard.State.LEAD, _hoard.crow_position(), _hoard.station_position(0), 18.0, 0.0, 66.0, 0.5)
	_cam.position = _hoard.station_position(0) + Vector2(0, -12)
	await _wait(_hoard._dur + 0.1)
	_hoard.dropped = 1
	_hoard._drop_age[0] = 0.0
	_hoard._go(CrowHoard.State.WAIT)
	await _wait(0.5)
	await _snap("raven_2_drop")
	await _wait(1.4)
	await _snap("raven_3_feather")
	_hoard.feathers = 1
	_hoard._start_flight(CrowHoard.State.LEAD, _hoard.crow_position(), _hoard.mound_position() + Vector2(0, -1), 0.0, 7.0, 66.0, -0.5)
	await _wait(_hoard._dur + 0.1)
	_hoard.revealed = true
	_hoard._go(CrowHoard.State.DIG)
	_cam.position = _hoard.mound_position() + Vector2(0, -16)
	await _wait(0.6)
	await _snap("raven_4_mound")
	print("PREVIEW CROW DONE")
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _run() -> void:
	if _raven:
		await _run_raven()
		return
	var snag: Vector2 = _hoard.snag_position()
	var mound: Vector2 = _hoard.mound_position()
	# the four perches side by side
	var others: Array[CrowHoard] = []
	for v: int in 4:
		var o: CrowHoard = CrowHoard.new()
		o.setup({"id": "preview_v%d" % v, "kind": "crow_hoard", "tile": [-40 + v * 4, -40], "mound": [-40 + v * 4, -30], "variant": v}, DataRegistry.table("puzzles").get("crow", {}) as Dictionary)
		o.manual = true
		add_child(o)
		o.set_night(1.0 if _night else 0.0)
		others.append(o)
	_cam.position = Vector2(-40 * 16 + 24 + 6 * 16, -40 * 16 - 10)
	await _wait(0.5)
	await _snap("0_variants")
	for o: CrowHoard in others:
		o.queue_free()
	_cam.position = snag + Vector2(0, -14)
	await _wait(0.6)
	await _snap("1_perch")
	_hoard._start_flight(CrowHoard.State.HOP, _hoard.crow_position(), snag + Vector2(-6, 36), 10.5, 0.0, 56.0, 0.3)
	await _wait(0.35)
	await _snap("2_hop")
	await _wait(1.2)
	_hoard._go(CrowHoard.State.GROUND)
	_cam.position = snag + Vector2(-6, 26)
	await _wait(0.5)
	await _snap("3_ground")
	_hoard._go(CrowHoard.State.CALL)
	await _wait(0.25)
	await _snap("4_call")
	await _wait(1.4)
	_hoard._start_flight(CrowHoard.State.LEAD, _hoard.crow_position(), mound + Vector2(-12, 3), 0.0, 0.0, 64.0, 0.55)
	await _wait(1.0)
	_cam.position = _hoard.crow_position() + Vector2(0, -20)
	await _snap("5_lead")
	await _wait(1.6)
	_hoard.revealed = true
	_hoard._go(CrowHoard.State.DIG)
	_cam.position = mound + Vector2(-4, -10)
	await _wait(1.0)
	await _snap("6_dig")
	_hoard._fly_home(false)
	await _wait(0.4)
	_hoard._rpc_dig(1)
	await _wait(0.12)
	await _snap("7_hoe")
	_hoard._rpc_dig(3)
	_chests.appear("preview", "common", mound, true, false, true)
	_cam.position = mound + Vector2(0, -16)
	var start: float = Time.get_ticks_msec() / 1000.0
	for t: float in [0.3, 0.5, 0.6, 0.68, 0.78, 0.9, 1.6]:
		var wait: float = t - (Time.get_ticks_msec() / 1000.0 - start)
		if wait > 0.0:
			await _wait(wait)
		await _snap("r_%03d" % int(t * 100.0))
	print("PREVIEW CROW DONE")
	get_tree().quit()
