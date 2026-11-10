extends Node
## Uses the normal player, a streamed cliff, and the real interaction action.

const WALL_FOOT: Vector2 = Vector2(7450, 9738)
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

class EmptyWorld extends WorldLevel:
	func _spawn_player(_id: int) -> void:
		pass

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(label)


func _obstacle(world: WorldLevel, point: Vector2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	var collider: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(18, 12)
	collider.shape = box
	body.add_child(collider)
	body.position = point
	world.add_child(body)
	return body


func _run() -> void:
	Jobs.threaded = false ## keep the headless renderer on the main thread
	if DisplayServer.get_name() == "headless":
		for action: StringName in InputMap.get_actions():
			for event: InputEvent in InputMap.action_get_events(action):
				if event is InputEventKey and (event as InputEventKey).keycode == KEY_NONE:
					(event as InputEventKey).keycode = (event as InputEventKey).physical_keycode
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	world.opening_over = true
	add_child(world)
	world.set_process(false)
	world.night.process_mode = Node.PROCESS_MODE_DISABLED
	var chunk: Vector2i = Vector2i((WALL_FOOT / 512.0).floor())
	if not world._chunks.has(chunk):
		world._load_chunk(chunk)
	var player: Player = TestLevel.PLAYER_SCENE.instantiate() as Player
	player.name = "1"
	player.position = WALL_FOOT
	world.get_node("Players").add_child(player)
	player.health.heal_full()
	player.facing = Vector2.UP
	await get_tree().physics_frame
	await get_tree().process_frame
	var climb: WallClimb = player.climb
	_check(not climb._landing(Vector2.UP).is_finite(), "Climbing cannot bypass the opening's story barrier")
	world.open_barrier("intro_corridor")
	await get_tree().process_frame
	await get_tree().physics_frame
	var landing: Vector2 = climb._landing(Vector2.UP)
	_check(landing.is_finite(), "The baked south face has a reachable upper ledge")
	if not landing.is_finite():
		get_tree().quit(1)
		return
	var low: float = Terrain.relief.level_at(WALL_FOOT)
	var skills: SkillTreeComponent = player.get_node("SkillTreeComponent") as SkillTreeComponent
	climb._request(Vector2.UP)
	_check(not climb.active() and not climb.offer(Vector2.UP, false), "The host and prompt both require the learned ability")
	player.progress.xp = Levels.xp_at(2)
	skills.request_learn(WallClimb.SKILL)
	_check(skills.points_free() == 0 and climb.offer(Vector2.UP, false), "A single point enables the wall prompt")
	Input.action_press("interact")
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_release("interact")
	_check(climb.active(), "The normal interaction action starts the ascent")
	var sprite: Sprite2D = player.get_node("Sprite2D") as Sprite2D
	_check(climb._position_at(WallClimb.SECONDS * 0.46).is_equal_approx(climb._position_at(WallClimb.SECONDS * 0.49)), "The first pull stops for a change of grip")
	await get_tree().create_timer(0.5).timeout
	_check(climb.active() and sprite.texture == WallClimb.SHEET and sprite.frame_coords.x >= WallClimb.FRAMES and sprite.frame_coords.y == 6 and not player.attack.visible, "The high north face uses the full climb pose")
	_check(player.global_position.distance_to(WALL_FOOT) > 2.0 and climb.save_position() == WALL_FOOT, "Mid-climb motion keeps the takeoff as the safe save point")
	await get_tree().create_timer(WallClimb.SECONDS).timeout
	_check(not climb.active() and player.global_position.is_equal_approx(landing) and Terrain.relief.level_at(landing) == low + 1.0, "Ellie lands one tier higher")
	_check(sprite.texture != WallClimb.SHEET and sprite.offset == Vector2(0, -23) and player.attack.visible, "The ground pose and arm return after landing")
	player.position += Vector2.DOWN * 5.0
	_check(not climb.offer(Vector2.DOWN, true) and not climb.active(), "E cannot climb down from the lip")
	player.request_teleport(WALL_FOOT)
	var prop: StaticBody2D = _obstacle(world, landing)
	await get_tree().physics_frame
	_check(not climb.offer(Vector2.UP, true), "A solid prop at the landing prevents a climb")
	prop.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	climb._request(Vector2.UP)
	_check(climb.active(), "Clearance allows another attempt")
	await get_tree().create_timer(0.4).timeout
	player.health.take_damage(2.0, WALL_FOOT, 0.0)
	_check(not climb.active() and player.global_position.is_equal_approx(WALL_FOOT), "A hit returns Ellie to the takeoff instead of leaving her in the wall")
	climb._request(Vector2.UP)
	await get_tree().create_timer(0.4).timeout
	prop = _obstacle(world, landing)
	await get_tree().create_timer(0.2).timeout
	_check(not climb.active() and player.global_position.is_equal_approx(WALL_FOOT), "An occupied landing during the ascent cancels safely")
	print("WALL CLIMB: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)
