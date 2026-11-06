extends Node
var failures: int = 0
func _ready() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
	else: print("PASS: ",label)
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.get_node("OpeningGuide").set_process(false)
	player.quests.set_physics_process(false)
	player.health.current = player.health.max_health
	player.sync_wound_visuals()
	player.position = Vector2(501,699)*16+Vector2(8,8)
	player.story_lock = true
	player._camera.reset_smoothing()
	world._stream(true)
	TimeManager.lock_at(0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ambush: AmbushScene = AmbushScene.new()
	ambush._player = player
	ambush._world = world
	var spots: Array[Vector2] = ambush._eye_spots()
	ambush.free()
	check(spots.size() == 3,"three valid ambush land spots")
	var spiders: Array[ShadowSpider] = []
	for spot: Vector2 in spots:
		spiders.append(world.spawn_story_spider("ambush_spider",spot,(player.position-spot).angle()))
	await get_tree().physics_frame
	if spiders.size() == 3:
		check(spiders[0]._birth._seed != spiders[1]._birth._seed and spiders[1]._birth._seed != spiders[2]._birth._seed,"each rift has its own shape and movement seed")
	for spider: ShadowSpider in spiders:
		check(spider.state == ShadowSpider.State.EMERGE and spider._body_shape.disabled and not spider._hurtbox.monitorable,"spawn gated: no AI, collision or hits")
	var elapsed: float = 0.0
	for time: float in [0.45,1.35,2.35,3.35,4.9]:
		await get_tree().create_timer(time-elapsed).timeout
		elapsed = time
		if time < 3.2:
			for i: int in spiders.size():
				check(spiders[i].global_position.distance_to(spots[i]) < 0.01,"creature stays rooted while forming")
		await RenderingServer.frame_post_draw
		for arg: String in OS.get_cmdline_user_args():
			if arg == "--capture": get_viewport().get_texture().get_image().save_png("/tmp/shadow-birth-%s.png" % str(time))
	for spider: ShadowSpider in spiders:
		check(spider.state != ShadowSpider.State.EMERGE and not spider._body_shape.disabled and spider._hurtbox.monitorable,"combat restored after emergence")
		check(not is_instance_valid(spider._birth),"ground distortion cleaned up")
	print("SHADOW BIRTH: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
