extends Node
var failures: int = 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.get_node("OpeningGuide").set_process(false)
	player.quests.set_physics_process(false)
	player.health.current = player.health.max_health
	player.sync_wound_visuals()
	player.position = Vector2(473,656)*16+Vector2(8,8)
	player._camera.reset_smoothing()
	world._stream(true)
	TimeManager.lock_at(0.5)
	await get_tree().physics_frame
	var wind: WorldWind = WorldWind.current
	check(wind != null,"world has a shared wind clock")
	var atlas: Image = MeadowDetails._atlas.get_image()
	check(atlas.get_width() == 26*16,"26 plant variants generated")
	for variant: int in 26:
		check(atlas.get_region(Rect2i(variant*16,0,16,20)).get_used_rect().has_area(),"plant %d is nonempty" % variant)
	var details: Array[Node] = get_tree().get_nodes_in_group("meadow_details")
	check(not details.is_empty(),"decorative batches loaded")
	var target: MeadowDetails
	for node: MeadowDetails in details:
		if not node.sources.is_empty() and (target == null or node.sources[0].distance_to(player.position) < target.sources[0].distance_to(player.position)):
			target = node
	if target == null:
		get_tree().quit(1)
		return
	var root: Vector2 = target.sources[0]
	var transform: Transform2D = target.multimesh.get_instance_transform_2d(0)
	var count: int = target.multimesh.instance_count
	check(target.stamp_segment(root-Vector2(18,0),root+Vector2(18,0),1.0),"swept movement contacts actual plants")
	target.advance_contacts(0.08)
	check(not target._bends.is_empty(),"contact field retains bending impulse")
	var cell: Vector2i = Vector2i(((root-target._origin)/8.0).floor())
	check(absf(target._field.get_pixelv(cell).r-0.5)>0.02,"contact reaches rendered field")
	for i: int in 14: target.advance_contacts(0.08)
	check(target._bends.is_empty() and absf(target._field.get_pixelv(cell).r-0.5)<0.005,"plants recover without permanent trail")
	check(target.multimesh.instance_count == count and target.multimesh.get_instance_transform_2d(0) == transform,"roots and plant population stay fixed")
	await _render_contact(wind)
	wind._tick = 0.0
	wind._previous.clear()
	wind._contacts(0.08)
	player.position += Vector2(1000,0)
	wind._contacts(0.08)
	check(target._bends.is_empty(),"teleport does not stamp a trail")
	player.position = Vector2(473,656)*16+Vector2(8,8)
	player._camera.reset_smoothing()
	get_tree().paused = true
	var before: float = wind.clock
	await get_tree().create_timer(0.2,true).timeout
	check(is_equal_approx(before,wind.clock),"wind freezes during paused dialogue")
	get_tree().paused = false
	Engine.time_scale = 0.25
	before = wind.clock
	await get_tree().create_timer(0.4,true,false,true).timeout
	check(wind.clock-before < 0.2 and wind.clock>before,"wind respects slow motion")
	Engine.time_scale = 1.0
	InputManager.ui_blocking = true
	wind._air.clear()
	wind._air_timer = 0.0
	wind._advance_air(0.1)
	check(wind._air.is_empty(),"no new air particles behind dialogue")
	InputManager.ui_blocking = false
	for i: int in 50: wind._release_seed(player.position)
	check(wind._air.size() == 8,"air population is strictly bounded")
	wind._advance_air(10.0)
	check(wind._air.size() <= 1,"old particles expire cleanly")
	# A visible left-to-right walk through a small decorative patch.
	var nearest: Vector2 = player.position
	var best: float = INF
	for node: MeadowDetails in details:
		for point: Vector2 in node.sources:
			var distance: float = point.distance_to(player.position)
			if distance < best:
				best = distance
				nearest = point
	player.story_lock = true
	player.position = nearest-Vector2(24,0)
	for i: int in 24:
		player.position.x += 2.0
		await get_tree().create_timer(0.02).timeout
	player.story_lock = false
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/wind-meadow-day.png")
	TimeManager.lock_at(0.0)
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/wind-meadow-night.png")
	atlas.resize(atlas.get_width()*4,atlas.get_height()*4,Image.INTERPOLATE_NEAREST)
	atlas.save_png("/tmp/wind-plants-atlas.png")
	print("WIND: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _render_contact(wind: WorldWind) -> void:
	wind.set_process(false)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(160,128)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var detail: MeadowDetails = MeadowDetails.new()
	detail.setup([{"pos":Vector2(80,100),"kind":14,"phase":0.0,"sway":1.0,"tint":Color.WHITE}])
	viewport.add_child(detail)
	detail.set_wind(0.0,Vector2.RIGHT,0.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var before: Image = viewport.get_texture().get_image()
	detail.stamp_segment(Vector2(64,100),Vector2(96,100),1.4)
	detail.advance_contacts(0.01)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var after: Image = viewport.get_texture().get_image()
	check(before.get_data() != after.get_data(),"rendered foliage visibly bends on contact")
	check(before.get_region(Rect2i(70,100,20,2)).get_data() == after.get_region(Rect2i(70,100,20,2)).get_data(),"rendered roots remain anchored")
	viewport.queue_free()
	await get_tree().process_frame
	wind.set_process(true)
