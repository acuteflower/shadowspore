extends Node2D
## Look study of the loot chests (docs/beutetruhen_konzept.md): the three tiers side by side on grass, all start opening together, captures at
## the given times. Offline, no world, no save.
##   Godot --rendering-driver opengl3 --path . tools/preview_loot_chests.tscn -- --dir=/abs/folder [--times=0,0.7,1.2,1.7,3] [--night] [--arrive]

var _dir: String = ""
var _times: Array[float] = [0.0, 0.7, 1.2, 1.7, 3.0]
var _night: bool = false
var _arrive: bool = false
var _chests: Array[LootChest] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.substr(6)
		elif arg.begins_with("--times="):
			_times.clear()
			for v: String in arg.substr(8).split(","):
				_times.append(v.to_float())
		elif arg == "--night":
			_night = true
		elif arg == "--arrive":
			_arrive = true
	var ground: ColorRect = ColorRect.new()
	ground.color = Color("2f4a3a") if not _night else Color("15202a")
	ground.size = Vector2(2000, 1200)
	ground.position = Vector2(-1000, -600)
	ground.z_index = -20
	add_child(ground)
	if _night:
		var dark: CanvasModulate = CanvasModulate.new()
		dark.color = Color(0.32, 0.3, 0.48)
		add_child(dark)
	var cam: Camera2D = Camera2D.new()
	cam.zoom = Vector2(2, 2)
	cam.position = Vector2(0, -20)
	add_child(cam)
	var x: float = -110.0
	for tier: String in ["common", "rare", "legendary"]:
		var chest: LootChest = LootChest.new()
		chest.id = "preview_" + tier
		chest.tier = tier
		chest.arrive = _arrive
		chest.position = Vector2(x, 20)
		add_child(chest)
		chest.set_night(1.0 if _night else 0.0)
		_chests.append(chest)
		x += 100.0
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	if _arrive:
		await get_tree().create_timer(1.4).timeout
	for chest: LootChest in _chests:
		chest.play_open(true)
	var start: float = Time.get_ticks_msec() / 1000.0
	for t: float in _times:
		var wait: float = t - (Time.get_ticks_msec() / 1000.0 - start)
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		if _dir != "":
			get_viewport().get_texture().get_image().save_png(_dir.path_join("chests_%s%s.png" % [str(t).replace(".", "_"), "_night" if _night else ""]))
	print("PREVIEW CHESTS DONE")
	get_tree().quit()
