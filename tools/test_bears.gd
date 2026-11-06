extends Node
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
var _checks: int = 0
var _failures: int = 0
var _population: BearPopulation

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)

func _make(at: Vector2, appearance: int, id: String) -> WildBear:
	var bear: WildBear = load("res://src/entities/wildlife/wild_bear.tscn").instantiate() as WildBear
	bear.name = id
	bear.appearance = appearance
	bear.family_id = "family"
	bear.position = at
	bear.home = Vector2.ZERO
	_population._residents.add_child(bear)
	bear.set_physics_process(false)
	return bear

func _run() -> void:
	_population = load("res://src/world/bear_population.tscn").instantiate() as BearPopulation
	add_child(_population)
	_population.setup(4, func(_p: Vector2, _s: String) -> bool: return true)
	_population.set_process(false)
	for x: int in range(-3, 4):
		for y: int in range(-3, 4):
			_population._active[Vector2i(x, y)] = true
	var bear: WildBear = _make(Vector2.ZERO, 0, "Mother")
	var cub: WildBear = _make(Vector2(90, 0), 2, "Cub")
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	player.position = Vector2(1000, 1000)
	add_child(player)
	player.set_physics_process(false)
	await get_tree().physics_frame
	_check(cub._adult() == bear and cub.is_cub(), "Cub lost its mother")
	cub._cub_life()
	_check(cub._moving and cub._end.distance_to(bear.position) < cub.position.distance_to(bear.position), "Cub did not follow")
	bear._sense()
	_check(not bear._danger and not bear._defending, "Calm bear starts aggressive")
	player.position = Vector2(60, 0)
	await get_tree().physics_frame
	bear._sense()
	_check(bear.mood == WoodlandMammal.Mood.FLEE and bear._end.x < 0.0 and not bear._defending, "Bear did not retreat first")
	# Persistent pursuit by one player, not a single close approach.
	player.velocity = Vector2.LEFT * 70.0
	for i: int in 42:
		bear._sense()
	_check(bear.mood == WoodlandMammal.Mood.REAR and bear._defending, "Persistent follower received no rearing warning")
	bear._elapsed = 1.8
	bear._process(0.0)
	_check(bear._sprite.frame % 44 == 43, "Rear did not hold upright pose")
	bear._elapsed = bear._duration
	player.position = Vector2(120, 0)
	bear._think()
	_check(bear.mood == WoodlandMammal.Mood.LOWER and not bear._defending, "Retreat during warning did not deescalate")
	bear._elapsed = bear._duration
	bear._think()
	_check(bear.mood != WoodlandMammal.Mood.SWIPE, "Bear attacked despite warning withdrawal")
	bear._defending = true
	bear._defense_left = 4.0
	bear._provoker = player
	bear._pressure[player.get_instance_id()] = 10.0
	player.position = Vector2(25, 0)
	bear._issue(WoodlandMammal.Mood.LOWER, 0.65)
	bear._elapsed = bear._duration
	bear._think()
	_check(bear.mood == WoodlandMammal.Mood.SWIPE and is_equal_approx(bear.facing, 0.0), "Bear did not aim a defensive swipe")
	await get_tree().physics_frame
	var hp: float = player.health.current
	bear._elapsed = 0.2
	bear._swipe_hit()
	_check(player.health.current == hp, "Swipe damaged during windup")
	bear._elapsed = 0.5
	bear._swipe_hit()
	_check(player.health.current == hp - 18.0, "Committed swipe missed nearby player")
	bear._elapsed = 0.55
	bear._swipe_hit()
	_check(player.health.current == hp - 18.0, "Swipe damaged more than once")
	player.health.current = hp
	player.position = Vector2(-25, 0)
	await get_tree().physics_frame
	bear._struck.clear()
	bear._last_swipe_elapsed = 0.0
	bear._elapsed = 0.5
	bear._swipe_hit()
	_check(player.health.current == hp, "Forward paw swipe hit behind bear")
	var wall: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(4, 40)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(12, 0)
	add_child(wall)
	player.position = Vector2(25, 0)
	await get_tree().physics_frame
	bear._struck.clear()
	bear._last_swipe_elapsed = 0.0
	bear._swipe_hit()
	_check(player.health.current == hp, "Swipe hit through solid cover")
	wall.queue_free()
	await get_tree().physics_frame
	bear._issue(WoodlandMammal.Mood.ALERT, 0.1)
	bear._defense_left = 0.0
	bear._elapsed = 1.0
	bear._think()
	_check(not bear._defending and bear._pressure.is_empty(), "Defensive chase did not expire")
	cub.position = Vector2(0, 80)
	player.position = Vector2(25, 80)
	for i: int in 60:
		cub._sense()
	_check(not cub._defending and cub.mood == WoodlandMammal.Mood.FLEE, "Cub became a combat attacker")
	player.position = Vector2(1000, 1000)
	bear._danger = false
	bear._safe_time = 10.0
	bear._issue(WoodlandMammal.Mood.ALERT, 0.1)
	bear._elapsed = 1.0
	var rabbit: WildRabbit = load("res://src/entities/wildlife/wild_rabbit.tscn").instantiate() as WildRabbit
	rabbit.position = Vector2(8, 0)
	add_child(rabbit)
	rabbit.set_physics_process(false)
	bear._prey = rabbit
	bear._hunt_left = 2.0
	bear._move_action(WoodlandMammal.Mood.CHASE, Vector2(10, 0), 1.0)
	bear._sense_left = 10.0
	bear._physics_process(0.016)
	_check(rabbit.captured and bear.mood == WoodlandMammal.Mood.FORAGE, "Hunt contact did not capture and feed")
	bear._issue(WoodlandMammal.Mood.SWIPE, 1.15)
	bear._elapsed = 0.5
	bear._process(0.0)
	_check(bear._sprite.hframes == 8 and bear._sprite.texture.resource_path.ends_with("bear_attack.png"), "Attack atlas not selected")
	cub._issue(WoodlandMammal.Mood.PLAY, 3.0)
	cub._process(0.0)
	_check(cub._sprite.hframes == 6 and cub._sprite.texture.resource_path.ends_with("bear_play.png"), "Cub play atlas not selected")
	# Continuous moving pursuit, rather than repeated stationary sensing alone.
	bear.position = Vector2.ZERO
	bear.home = Vector2.ZERO
	bear._defending = false
	bear._pressure.clear()
	bear._provoker = null
	bear._issue(WoodlandMammal.Mood.REST, 0.1)
	cub.position = Vector2(1000, 1000)
	for frame: int in 65:
		player.position = bear.position + Vector2(65, 0)
		player.velocity = Vector2.LEFT * 60.0
		bear._sense_left = 0.0
		bear._physics_process(0.15)
		if bear.mood == WoodlandMammal.Mood.REAR:
			break
	_check(bear.mood == WoodlandMammal.Mood.REAR and bear.position.x < -50.0, "Moving pursuit did not build pressure while bear escaped")
	# Mother's shorter warning threshold when a player crowds her cub.
	bear.position = Vector2.ZERO
	bear.home = Vector2.ZERO
	bear._defending = false
	bear._pressure.clear()
	bear._provoker = null
	bear._issue(WoodlandMammal.Mood.REST, 0.1)
	cub.position = Vector2(80, 0)
	player.position = Vector2(85, 0)
	player.velocity = Vector2.ZERO
	for frame: int in 29:
		bear._sense()
	_check(bear.mood == WoodlandMammal.Mood.REAR, "Mother did not warn sustained crowding of cub")
	bear._pressure[player.get_instance_id()] = 5.0
	player.position = Vector2(1000, 1000)
	bear._defending = false
	bear._provoker = null
	bear._issue(WoodlandMammal.Mood.ALERT, 0.5)
	for frame: int in 25:
		bear._sense()
	_check(float(bear._pressure.get(player.get_instance_id(), 0.0)) == 0.0, "Pursuit pressure failed to decay after leaving")
	# Real deterministic population, including safe families and hard cap.
	bear.queue_free()
	cub.queue_free()
	rabbit.queue_free()
	player.remove_from_group("players")
	player.queue_free()
	await get_tree().physics_frame
	for x: int in range(-3, 4):
		for y: int in range(-3, 4):
			_population._populate(Vector2i(x, y))
	_check(_population._count("bear") > 0 and _population._count("bear") <= 6, "Natural bear population missing or over cap")
	var cub_count: int = 0
	for node: Node in _population._residents.get_children():
		if (node as WildBear).is_cub():
			cub_count += 1
			_check((node as WildBear)._adult() != null, "Natural cub spawned without parent")
	_check(cub_count > 0, "Natural families have no cubs")
	_population._active.clear()
	_population._collect()
	await get_tree().physics_frame
	_check(_population._residents.get_child_count() == 0, "Unloaded families were not cleaned up")
	print("Bears: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
