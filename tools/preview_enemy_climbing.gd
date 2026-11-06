extends Node
## Actual streamed-world cliff pursuit, offline, without saves or a game socket.
## Godot --path . tools/preview_enemy_climbing.tscn [-- --capture=/absolute/path.png]
## Headless --fixed-fps 60 with -- --check verifies a complete real-world ascent.

const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")

class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _pair(spider: ShadowSpider, near: Vector2) -> PackedVector2Array:
	for node: Node in get_tree().get_nodes_in_group("relief_walls"):
		for child: Node in node.get_children():
			var shape: CollisionShape2D = child as CollisionShape2D
			if shape == null or not shape.shape is RectangleShape2D:
				continue
			var size: Vector2 = (shape.shape as RectangleShape2D).size
			if size.y < 12.0 or size.x < 18.0:
				continue
			for side: float in [0.0, -0.25, 0.25]:
				var from: Vector2 = shape.global_position + Vector2(size.x * side, size.y * 0.5 + 18.0)
				if from.distance_to(near) > 650.0 or not spider._navigation.can_occupy(from):
					continue
				var to: Vector2 = spider._climb_link(from, Vector2(0, -12))
				if not to.is_finite():
					continue
				var player_at: Vector2 = to + Vector2(0, -38)
				if spider._same_floor(to, player_at) and spider._navigation.can_occupy(player_at):
					return PackedVector2Array([from, to, player_at])
	return PackedVector2Array()


func _run() -> void:
	var capture: String = ""
	var check: bool = OS.get_cmdline_user_args().has("--check")
	var route: bool = OS.get_cmdline_user_args().has("--route")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	TimeManager.time_of_day = 0.75
	var world: WorldLevel = WORLD_SCENE.instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	var camera: Camera2D = Camera2D.new()
	camera.position = world._spawn_position(0) + Vector2(-80, -620)
	camera.zoom = Vector2(1.5, 1.5)
	world.add_child(camera)
	world.editor_camera = camera
	for frame: int in 18:
		await get_tree().physics_frame
	var spider: ShadowSpider = load("res://src/entities/enemies/shadow_spider.tscn").instantiate() as ShadowSpider
	world.get_node("Enemies").add_child(spider)
	spider.set_physics_process(false)
	var pair: PackedVector2Array = _pair(spider, camera.position)
	if pair.is_empty():
		push_error("No loaded clear real-world cliff for the climbing preview")
		get_tree().quit(1)
		return
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	player.position = pair[2]
	world.get_node("Players").add_child(player)
	player.set_physics_process(false)
	player.health.max_health = 1000.0
	player.health.current = 1000.0
	(player.get_node("Camera2D") as Camera2D).enabled = false
	camera.position = pair[0].lerp(pair[1], 0.5) + Vector2(0, -22)
	spider.position = pair[0]
	spider._target = player
	spider._grapple_cd = 999.0
	# Show the validated physical climb even when an inexpensive real stair
	# detour would win A*. Automatic link selection is covered by the route test.
	if route:
		spider._set_state(ShadowSpider.State.CHASE)
	else:
		spider._prepare_climb(pair[1])
	spider.set_physics_process(true)
	print("Real cliff: ", pair, " heights=", spider._height_at(pair[0]), "/", spider._height_at(pair[1]))
	var climbed: bool = false
	var captured: bool = false
	for frame: int in 900:
		await get_tree().physics_frame
		climbed = climbed or spider.state == ShadowSpider.State.CLIMB
		if not captured and not capture.is_empty() and spider.state == ShadowSpider.State.CLIMB and spider._state_time > spider._climb_duration() * 0.45:
			await RenderingServer.frame_post_draw
			var error: Error = get_viewport().get_texture().get_image().save_png(capture)
			print("Cliff capture: ", error_string(error))
			captured = error == OK
			if not check:
				get_tree().quit(error)
				return
		if check and (climbed or route) and player.health.current < 1000.0:
			var safe: bool = spider._climb_walls.is_empty() and spider._same_floor(spider.position, player.position)
			print("Actual cliff pursuit: climbed=", climbed, ", arrived=", safe, ", reached player=true")
			get_tree().quit(0 if safe else 1)
			return
	if check or not capture.is_empty():
		push_error("Cliff pursuit did not finish: climbed=%s state=%s at=%s target=%s health=%s" % [climbed, ShadowSpider.State.keys()[spider.state], spider.position, player.position, player.health.current])
		get_tree().quit(1)
