extends Node
## Look study for docs/stadtbau_konzept.md in the real world, offline, no save access:
## `Godot --rendering-driver opengl3 --path . tools/preview_town_build.tscn -- --dir=/abs/folder [--piece=stockpile] [--times=0.05,0.35,0.7,1.4] [--night] [--mode=done|site|menu|banner|level]`
## done: a site of `piece` is finished by the host and pictures are taken that many seconds after the consecration started;
## site: the site at 45 % while she lends a hand; menu: the build plan open; banner: the town banner when she walks in; level: the level ceremony.

var _dir: String = ""


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = _dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 24):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 8.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


func _run() -> void:
	var piece: String = "stockpile"
	var times: Array[float] = [0.05, 0.35, 0.7, 1.4]
	var night: bool = false
	var mode: String = "done"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): _dir = arg.get_slice("=", 1)
		elif arg.begins_with("--piece="): piece = arg.get_slice("=", 1)
		elif arg.begins_with("--mode="): mode = arg.get_slice("=", 1)
		elif arg == "--night": night = true
		elif arg.begins_with("--times="):
			times.clear()
			for t: String in arg.get_slice("=", 1).split(","):
				times.append(t.to_float())
	DirAccess.make_dir_recursive_absolute(_dir)
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	player.request_teleport(hut.position + Vector2(20, 150))
	await _frames(120)
	player.quests.set_flag("rebuild_done")
	await _frames(70)
	for item: String in ["wood", "stone", "glow_cap", "plant_fiber", "plank", "iron_ore"]:
		player.inventory.give(item, 90)
	town.residents["gustav"] = {"trust": 0, "talked": -1}
	TimeManager.time_of_day = 0.96 if night else 0.5
	var at: Vector2 = _site(town, piece, hut.position + Vector2(-60, 190))
	player.request_teleport(at + Vector2(-70, 46))
	await _frames(30)
	if mode == "menu":
		var builder: BuildMode = town.build_mode()
		InputManager.using_mouse = false
		builder.set_active(true)
		var cats: Array[Dictionary] = builder.categories()
		for i: int in cats.size():
			if piece in TownRules.in_category(String(cats[i].id)):
				builder.category = i
		builder.menu.deal()
		builder.select(piece)
		player.facing = Vector2(1, -0.5)
		await _frames(90)
		await _shot("menu")
		get_tree().quit()
		return
	if mode == "banner":
		town._inside = false
		town._entered_day = -1
		player.request_teleport(hut.position + Vector2(0, 600))
		await _frames(30)
		player.request_teleport(hut.position + Vector2(10, 120))
		for t: float in times:
			await get_tree().create_timer(t).timeout
			await _shot("banner_%.2f" % t)
		get_tree().quit()
		return
	if mode == "level":
		town.emit_event("level_up", {"level": 2, "name": TownRules.level_name(2)})
		for t: float in times:
			await get_tree().create_timer(t).timeout
			await _shot("level_%.2f" % t)
		get_tree().quit()
		return
	print("check: '", town.check_place(piece, at, player), "' site: '", town.check_site(piece, at), "'")
	town._host_place(piece, at, 0, 1)
	var id: int = town.next_id - 1
	print("placed ", piece, " at ", at - hut.position, " id ", id)
	await _frames(40)
	if mode == "site":
		(town.structures[id] as Dictionary).g = 450
		town._progress[id] = 450.0
		(town._views[id] as TownStructure).set_progress(450)
		var rect: Rect2 = town.rect_of(id)
		player.request_teleport(Vector2(rect.position.x - 14.0, rect.end.y + 6.0))
		await _frames(20)
		town.lend_hand(player, id)
		await get_tree().create_timer(1.7).timeout
		await _shot("site")
		get_tree().quit()
		return
	await _shot("before")
	Engine.time_scale = 0.2 ## the preview renders slowly: slow the moment down so every picture lands where it should
	town._progress[id] = float(TownManager.PROGRESS_FULL) - 1.0
	(town.structures[id] as Dictionary).g = TownManager.PROGRESS_FULL - 1
	var started: int = Time.get_ticks_msec()
	while (town.structures[id] as Dictionary).g < TownManager.PROGRESS_FULL:
		await get_tree().process_frame
	started = Time.get_ticks_msec()
	for t: float in times:
		while float(Time.get_ticks_msec() - started) / 1000.0 * Engine.time_scale < t:
			await get_tree().process_frame
		await _shot("done_%.2f" % t)
	print("cleared cells now ", town.cleared.size(), " stock ", town.stock)
	get_tree().quit()
