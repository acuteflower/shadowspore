extends Node
## Offline regression of routed pursuit and deliberate cliff traversal, no saves/socket.
## Godot --headless --path . tools/test_enemy_navigation.tscn

class TestRelief:
	extends Relief
	var upper_level: float = 1.0
	var gap: bool = false
	func is_land(x: int, y: int) -> bool:
		return x >= -40 and x <= 40 and y >= -40 and y <= 40
	func level_at(point: Vector2) -> float:
		if gap and point.x > 68.0 and point.x < 116.0 and point.y >= 0.0 and point.y < 32.0:
			return 1.0 - point.y / 32.0
		return upper_level if point.y < 0.0 else 0.0

var _checks: int = 0
var _failures: int = 0
var _level: Node2D
var _player: Player
var _spider: ShadowSpider
var _relief: TestRelief
var _walls: Array[StaticBody2D] = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)


func _wall(rect: Rect2, cliff: bool = true) -> StaticBody2D:
	var wall: StaticBody2D = StaticBody2D.new()
	var collider: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	collider.shape = box
	wall.position = rect.get_center()
	wall.add_child(collider)
	if cliff:
		wall.add_to_group("relief_walls")
	_level.add_child(wall)
	_walls.append(wall)
	return wall


func _reset(from: Vector2, to: Vector2) -> void:
	_spider._set_state(ShadowSpider.State.IDLE)
	_spider.position = from
	_spider.velocity = Vector2.ZERO
	_spider._target = _player
	_spider._climb_cd = 0.0
	_spider._grapple_cd = 999.0
	_spider._health.current = 48.0
	_spider._rig._feet_ready = false
	_spider._set_state(ShadowSpider.State.CHASE)
	_player.position = to
	_player.health.max_health = 1000.0
	_player.health.current = 1000.0
	_player.health.invulnerable_seconds = 0.0


func _tick() -> void:
	await get_tree().physics_frame
	_spider._physics_process(1.0 / 60.0)
	_spider._process(1.0 / 60.0)


func _run() -> void:
	_level = Node2D.new()
	add_child(_level)
	_relief = TestRelief.new()
	Terrain.relief = _relief
	_player = load("res://src/entities/player/player.tscn").instantiate() as Player
	_player.name = "2"
	_level.add_child(_player)
	_player.set_physics_process(false)
	_spider = load("res://src/entities/enemies/shadow_spider.tscn").instantiate() as ShadowSpider
	_level.add_child(_spider)
	_spider.set_physics_process(false)
	_spider.set_process(false)
	# A walkable stair-sized opening lies off the direct pursuit line.
	_relief.gap = true
	_wall(Rect2(-180, 0, 248, 32))
	_wall(Rect2(116, 0, 64, 32))
	_reset(Vector2(0, 85), Vector2(0, -55))
	_spider._climb_cd = 999.0
	await get_tree().physics_frame
	_check(_spider._find_target() == _player, "Spider could not notice a player above a cliff")
	var passed_stairs: bool = false
	var used_climb: bool = false
	var routed_nodes: int = 0
	for frame: int in 420:
		await _tick()
		passed_stairs = passed_stairs or (_spider.position.x > 72.0 and _spider.position.x < 112.0 and _spider.position.y < 36.0 and _spider.position.y > -8.0)
		used_climb = used_climb or _spider.state in [ShadowSpider.State.CLIMB, ShadowSpider.State.CLIMB_WINDUP]
		routed_nodes = maxi(routed_nodes, _spider._navigation.expanded)
		if _player.health.current < 1000.0:
			break
	_check(passed_stairs and not used_climb, "Enemy did not walk around to the open ascent")
	_check(_spider.position.y < 0.0 and _player.health.current < 1000.0, "Enemy never reached or threatened the player above the stairs")
	_check(routed_nodes > 0, "Pursuit did not exercise path search")
	print("Stair route: ", _spider.position, " expanded=", routed_nodes)
	for wall: StaticBody2D in _walls:
		wall.queue_free()
	_walls.clear()
	await get_tree().physics_frame
	# No nearby opening: explicitly grapple onto the lip and pull the body over it.
	_relief.gap = false
	_wall(Rect2(-180, 0, 360, 32))
	_reset(Vector2(0, 70), Vector2(0, -55))
	await get_tree().physics_frame
	var seen: Dictionary = {}
	var hurt_mid_climb: bool = false
	var continuous: bool = true
	for frame: int in 420:
		var before: Vector2 = _spider.position
		await _tick()
		seen[_spider.state] = true
		continuous = continuous and _spider.position.distance_to(before) < 5.0
		if _spider.state == ShadowSpider.State.CLIMB and not hurt_mid_climb:
			_spider._health.take_damage(5.0, _player.position, 80.0)
			hurt_mid_climb = _spider.state == ShadowSpider.State.CLIMB and _spider._health.current == 43.0
		if _player.health.current < 1000.0:
			break
	_check(seen.has(ShadowSpider.State.CLIMB_WINDUP) and seen.has(ShadowSpider.State.CLIMB), "Spider never prepared and performed a cliff climb")
	_check(continuous, "Climbing teleported the body instead of traversing the wall")
	_check(hurt_mid_climb, "Climbing spider became invulnerable or was stranded by a hit")
	_check(_spider.position.y < 0.0 and _player.health.current < 1000.0, "Climbing spider did not reach the upper player")
	_check(_spider._climb_walls.is_empty() and _spider.get_collision_exceptions().is_empty(), "Climb left permanent world-collision exceptions")
	print("Upper climb: ", _spider.position, " states=", seen.keys())
	# Reverse direction: the same wall needs a controlled descent rather than a fall/warp.
	_reset(Vector2(0, -45), Vector2(0, 90))
	seen.clear()
	for frame: int in 420:
		await _tick()
		seen[_spider.state] = true
		if _player.health.current < 1000.0:
			break
	_check(seen.has(ShadowSpider.State.CLIMB) and _spider.position.y > 41.0 and _player.health.current < 1000.0, "Spider failed to descend toward a lower player")
	_check(_spider._climb_walls.is_empty(), "Descending spider retained wall exceptions")
	print("Lower climb: ", _spider.position)
	# Occupy the landing after the climb starts. Return safely instead of entering the prop.
	_reset(Vector2(0, 70), Vector2(0, -90))
	var blocked: bool = false
	var retreat: bool = false
	var obstruction: StaticBody2D
	for frame: int in 300:
		await _tick()
		if _spider.state == ShadowSpider.State.CLIMB and _spider._state_time > 0.25 and not blocked:
			obstruction = _wall(Rect2(_spider.anchor - Vector2(10, 10), Vector2(20, 20)), false)
			blocked = true
		retreat = retreat or _spider.state == ShadowSpider.State.CLIMB_RETREAT
		if retreat and _spider.state == ShadowSpider.State.RECOVER:
			break
	_check(blocked and retreat and _spider.position.y > 41.0, "A blocked landing did not send the spider safely back")
	_check(_spider._climb_walls.is_empty(), "Aborted climb retained collision exceptions")
	if is_instance_valid(obstruction):
		obstruction.queue_free()
	await get_tree().physics_frame
	# A tree/building is not a climb link, even if the terrain beyond it is higher.
	for wall: StaticBody2D in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()
	await get_tree().physics_frame
	_wall(Rect2(-180, 0, 360, 32), false)
	_reset(Vector2(0, 48), Vector2(0, -55))
	await get_tree().physics_frame
	_check(not _spider._climb_link(_spider.position, Vector2(0, -12)).is_finite(), "Spider treated an ordinary world obstacle as a cliff")
	for wall: StaticBody2D in _walls:
		wall.queue_free()
	_walls.clear()
	await get_tree().physics_frame
	_wall(Rect2(-180, 0, 360, 32))
	var void_wall: StaticBody2D = _wall(Rect2(-12, 6, 24, 20), false)
	await get_tree().physics_frame
	_check(not _spider._can_climb(Vector2(0, 48), Vector2(0, -14)), "Climb ignored solid void/prop collision behind a cliff")
	void_wall.queue_free()
	await get_tree().physics_frame
	_relief.upper_level = 2.0
	_check(not _spider._can_climb(Vector2(0, 48), Vector2(0, -14)), "Spider climbed multiple height levels in one move")
	_relief.upper_level = 1.0
	# Attacks cannot reach across different heights even beside the end of a wall.
	_reset(Vector2(230, 10), Vector2(230, -16))
	await get_tree().physics_frame
	_spider._set_state(ShadowSpider.State.WINDUP)
	_spider._set_state(ShadowSpider.State.STRIKE)
	_spider._state_time = 0.2
	_spider._strike()
	_spider.anchor = _player.position
	_spider._grapple_hit()
	_check(_player.health.current == 1000.0, "An attack hit a player on another height level")
	# Heavy hits can stop the preparation; once on the wall damage still applies
	# but movement must finish/retreat so restoring collision cannot strand a live body.
	_reset(Vector2(0, 48), Vector2(0, -90))
	await get_tree().physics_frame
	_spider._prepare_climb(Vector2(0, -14))
	_spider._health.take_damage(5.0, _player.position, 80.0)
	_check(_spider.state == ShadowSpider.State.HURT and _spider.get_collision_exceptions().is_empty(), "Heavy hit failed to interrupt the climb preparation safely")
	_reset(Vector2(0, 48), Vector2(0, -90))
	_spider._prepare_climb(Vector2(0, -14))
	_spider._set_state(ShadowSpider.State.CLIMB)
	_check(not _spider.get_collision_exceptions().is_empty(), "Climb did not temporarily release cliff collision")
	_spider._health.take_damage(100.0, _player.position, 80.0)
	_check(_spider.state == ShadowSpider.State.DEAD and _spider.get_collision_exceptions().is_empty(), "Death left collision exceptions behind")
	print("Enemy navigation: %d checks, %d failures" % [_checks, _failures])
	Terrain.relief = null
	_level.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
