extends Node
## The fields in the real world (docs/farming.md). `-- --capture=/abs/file.png [--night] [--zoom=3]` founds the town, builds two fields side by side and one apart, tills, waters
## and sows beds in every stage (the ripe glow crops show at night) and saves a screenshot. Offline, no save access. Use `--rendering-driver opengl3`.

func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 18):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 8.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


func _put(town: TownManager, piece: String, pos: Vector2) -> int:
	var before: int = town.next_id
	town._host_place(piece, pos, 0, 1)
	var id: int = town.next_id - 1
	if town.next_id == before:
		print("PLACE FAILED ", piece, " ", town.check_place(piece, pos, town.local_player()))
		return -1
	(town.structures[id] as Dictionary).g = TownManager.PROGRESS_FULL
	town._rpc_done(id)
	return id


func _cell(farm: FarmManager, field_id: int, index: int, crop: String, stage: int, wet: bool) -> void:
	var state: Dictionary = {"t": 1, "u": TimeManager.day}
	if crop != "":
		state["c"] = crop
		state["a"] = stage
		state["p"] = 0
		state["m"] = 0
	if wet:
		state["w"] = TimeManager.day + 1
	farm._rpc_cell(field_id, index, state, "")


func _run() -> void:
	var capture: String = ""
	var night: bool = false
	var zoom: float = 3.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.get_slice("=", 1)
		elif arg == "--night":
			night = true
		elif arg.begins_with("--zoom="):
			zoom = arg.get_slice("=", 1).to_float()
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	world.finish_opening()
	player.request_heal()
	TimeManager.set_time(0.5)
	player.request_teleport(hut.position + Vector2(20, 150))
	await _frames(120)
	player.quests.set_flag("rebuild_done")
	await _frames(70)
	for item: String in ["wood", "stone", "glow_cap", "plant_fiber"]:
		player.inventory.give(item, 90)
	town.unlock("farming")
	await _frames(2)
	var lamp: Vector2 = _site(town, "lamp_post", hut.position + Vector2(-60, 130))
	_put(town, "lamp_post", lamp)
	var base: Vector2 = _site(town, "field", hut.position + Vector2(60, 150))
	var first: int = _put(town, "field", base)
	var second_at: Vector2 = TownRules.snapped_position("field", base + Vector2(48, 0)) ## right next to it: one big bed
	var second: int = _put(town, "field", second_at) if town.check_site("field", second_at) == "" else -1
	var third_at: Vector2 = _site(town, "field", base + Vector2(-90, 10))
	var third: int = _put(town, "field", third_at) if third_at != Vector2.INF else -1
	await _frames(4)
	var farm: FarmManager = town.farm
	# the first field: every stage, wet and dry
	var plan: Array = [["", 0, false], ["tuber", 0, true], ["tuber", 1, true], ["tuber", 3, false], ["ember_carrot", 2, true], ["ember_carrot", 3, true], ["night_beet", 1, false], ["night_beet", 3, true], ["wound_leaf", 3, false]]
	for k: int in plan.size():
		_cell(farm, first, k, String((plan[k] as Array)[0]), int((plan[k] as Array)[1]), bool((plan[k] as Array)[2]))
	if second >= 0:
		for k: int in [0, 1, 3, 4, 6, 7]:
			_cell(farm, second, k, "tuber" if k % 2 == 0 else "wound_leaf", 2, k < 4)
	if third >= 0:
		_cell(farm, third, 4, "", 0, true)
		_cell(farm, third, 1, "", 0, false)
	await _frames(6)
	if not night:
		TimeManager.set_time(0.5)
	if night:
		TimeManager.set_time(0.93)
		await _frames(50)
	var center: Vector2 = town.rect_of(first).get_center() + Vector2(24, 0)
	player.global_position = center + Vector2(0, 70)
	await _frames(20)
	if player.view_camera() != null:
		player.view_camera().zoom = Vector2(zoom, zoom)
		player.view_camera().global_position = center
		player.view_camera().position_smoothing_enabled = false
	await _frames(240)
	if capture != "":
		get_viewport().get_texture().get_image().save_png(capture)
		print("fields placed: ", first, " ", second, " ", third)
		print("saved ", capture, " fields ", first, " ", second, " ", third)
		get_tree().quit()
