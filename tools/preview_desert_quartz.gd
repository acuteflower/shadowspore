extends Node
## Visual verification captures for mineable desert quartz rocks (`sun_quartz_rock`) emerging from ground quartz outcrops.
## Run: godot --rendering-driver opengl3 --path . res://tools/preview_desert_quartz.tscn -- --dir=/abs/folder

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
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	add_child(world)
	var hero: Player = world._players.get_child(0) as Player
	hero.visible = false
	hero.get_node("OpeningGuide").set_process(false)
	hero.quests.set_physics_process(false)
	var hud: CanvasLayer = world.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	for child: Node in world.get_children():
		var cl: CanvasLayer = child as CanvasLayer
		if cl != null and cl.name != "MoodGrade":
			cl.visible = false

	# Locate rich natural sun_quartz_rock clusters in Sonnenquarz-Öde
	var spots: Array[Vector2] = []
	for cy: int in range(3, 8):
		for cx: int in range(21, 31):
			var rect: Rect2i = Rect2i(Vector2i(cx, cy) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			var qrocks: Array[Vector2] = []
			for entry: Dictionary in world._generator.props_for_chunk(rect):
				if String(entry.kind) == "sun_quartz_rock":
					qrocks.append(entry.pos as Vector2)
			if qrocks.size() >= 2:
				spots.append(qrocks[0])
			elif qrocks.size() == 1 and spots.size() < 3:
				spots.append(qrocks[0])
			if spots.size() >= 4:
				break
		if spots.size() >= 4:
			break

	var focus: Vector2 = spots[0] if not spots.is_empty() else Vector2(820.0, 165.0) * 16.0
	var cam: Camera2D = hero.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		for c: Node in hero.get_children():
			if c is Camera2D:
				cam = c as Camera2D
				break

	TimeManager.unlock()
	TimeManager.locked = true
	TimeManager.time_of_day = 0.5
	hero.request_teleport(focus)
	for _i: int in 90:
		await get_tree().process_frame
	await _shot(dir, "natural_day")

	if cam != null:
		cam.zoom = Vector2(2.2, 2.2)
	for _i: int in 15:
		await get_tree().process_frame
	await _shot(dir, "natural_zoom")

	if cam != null:
		cam.zoom = Vector2(1.0, 1.0)
	TimeManager.time_of_day = 0.0
	for _i: int in 45:
		await get_tree().process_frame
	await _shot(dir, "natural_night")

	if spots.size() >= 2:
		TimeManager.time_of_day = 0.5
		hero.request_teleport(spots[1])
		for _i: int in 75:
			await get_tree().process_frame
		await _shot(dir, "natural_cluster_2")

	# Oasis water plants (Fix 2) + Date palms unpicked vs picked (Fix 4) + Forced storm rainless desert (Fix 3)
	var oasis_center: Vector2 = Vector2(708.0, 139.0) * 16.0
	TimeManager.time_of_day = 0.5
	hero.request_teleport(oasis_center)
	for _i: int in 90:
		await get_tree().process_frame

	# Find dense water flora spot & sun_palm cluster near oasis_lagoon
	var water_spot: Vector2 = oasis_center
	var rds: Array[RiverDetails] = []
	_collect_rds(world, rds)
	for rd: RiverDetails in rds:
		for idx_w: int in rd._sprites.size():
			if rd._rows[idx_w] == 20:
				water_spot = rd._sprites[idx_w].global_position
				break
		if water_spot != oasis_center:
			break

	hero.request_teleport(water_spot)
	if cam != null:
		cam.zoom = Vector2(2.4, 2.4)
	for _i: int in 30:
		await get_tree().process_frame
	await _shot(dir, "oasis_water_t0")
	# Advance ~1.4s of real RiverDetails._process time so state toggles 0 -> 1
	for rd: RiverDetails in rds:
		rd._process(1.35)
	for _i: int in 6:
		await get_tree().process_frame
	await _shot(dir, "oasis_water_t1")

	# Locate sun_palm trees around oasis_lagoon
	var palms: Array[FirTree] = []
	_collect_palms(world, palms)
	if not palms.is_empty():
		var palm_focus: Vector2 = palms[0].global_position + Vector2(0.0, -56.0)
		hero.request_teleport(palm_focus)
		if cam != null:
			cam.zoom = Vector2(1.55, 1.55)
		for _i: int in 45:
			await get_tree().process_frame
		await _shot(dir, "oasis_palms_unpicked")

		TimeManager.time_of_day = 0.0
		for _i: int in 30:
			await get_tree().process_frame
		await _shot(dir, "oasis_palms_night")

		TimeManager.time_of_day = 0.5
		palms.clear()
		_collect_palms(world, palms)
		for p: FirTree in palms:
			p.apply_state({"p": 1, "k": "sun_palm"}, "pick")
		for _i: int in 25:
			await get_tree().process_frame
		await _shot(dir, "oasis_palms_picked")

	# Forced storm in desert oasis (Fix 3): verify clear dry air, zero rain streaks, zero water drop rings
	if cam != null:
		cam.zoom = Vector2(1.2, 1.2)
	hero.request_teleport(water_spot + Vector2(-40.0, -20.0))
	if WeatherManager.current != null:
		WeatherManager.current.force("storm", 0.0)
	for _i: int in 60:
		if WeatherManager.current != null:
			WeatherManager.current.follow(false, 0.5)
		await get_tree().process_frame
	await _shot(dir, "desert_forced_storm")
	if WeatherManager.current != null:
		WeatherManager.current.release()

	print("DESERT QUARTZ PREVIEW OK (%d spots, %d palms)" % [spots.size(), palms.size()])
	get_tree().quit()


func _collect_rds(node: Node, out: Array[RiverDetails]) -> void:
	if node is RiverDetails:
		out.append(node as RiverDetails)
	for c: Node in node.get_children():
		_collect_rds(c, out)


func _collect_palms(node: Node, out: Array[FirTree]) -> void:
	if node is FirTree and (node as FirTree).kind == "sun_palm":
		out.append(node as FirTree)
	for c: Node in node.get_children():
		_collect_palms(c, out)
