class_name GustavEscortScene
extends Node
## Quest `gustav_rescue`, step `escort` (event `escort:gustav`, started when he has packed; a save that stopped there starts it again): Gustav follows Ellie home through the dusk.
## It is the knight walk turned around: an invisible walker steered by `EnemyNavigation` follows her (he waits and calls when she runs ahead), the goal is the nearest lit ground between
## the wagon and the town. On the way three waves of normal shadow spiders (1 / 2 / 1, never more than two at once) rise ahead of him; they ignore him, so the "he gets attacked" part is
## staged: when one is close he stumbles (`escort_hit`) or swings his hammer (12 damage, `escort_hammer`) every 6 s. After the second wave he gives her bread and berries when she is hurt.
## The sky darkens towards the town (the clock runs to 0.80 over the route, only if it is day), `NightDirector.story_hold` keeps the real night waves away. If she falls the wave dissolves
## and comes again when she is back with him. Arriving in the light sets the flag `gustav_at_light`. Solo / host only, a child of the player.

const LEGS: float = 190.0
const WAIT_FAR: float = 150.0
const GO_NEAR: float = 95.0
const STOP_NEAR: float = 46.0
const NAV: Dictionary = {"cell_size": 12, "nodes_per_frame": 72, "usec_per_frame": 1600, "max_nodes": 5200, "search_margin": 272, "target_repath_distance": 24,
		"refresh_seconds": 2.5, "retry_seconds": 0.5, "climb_penalty": 135}
## [progress at which the wave rises, spiders, bark]
const WAVES: Array[Array] = [[0.22, 1, "escort_wave_1"], [0.5, 2, "escort_wave_2"], [0.8, 1, "escort_wave_3"]]
const WAITS: Array[String] = ["escort_wait_a", "escort_wait_b"]
const MAX_ALIVE: int = 2
const HAMMER_DAMAGE: float = 12.0
const GAG_EVERY: float = 6.0
const DUSK_AT: float = 0.80 ## the clock when he arrives
const DUSK_BY: float = 0.85 ## progress at which the dusk is complete

var _player: Player
var _world: WorldLevel
var _town: TownManager
var _wagon: GustavWagon
var _gustav: StoryGustav
var _walker: CharacterBody2D
var _nav: EnemyNavigation
var _goal: Vector2
var _total: float = 1.0
var _leg: Vector2 = Vector2.INF
var _waiting: bool = false
var _wait_time: float = 0.0
var _wait_calls: int = 0
var _stuck: float = 0.0
var _best: float = INF
var _clip: String = ""
var _wave: int = 0 ## the next wave to rise
var _alive: Array[ShadowSpider] = []
var _wave_open: bool = false ## a wave is out there
var _rested: bool = false
var _gag_clock: float = 3.0
var _gags: int = 0
var _gag_left: float = 0.0
var _t0: float = 0.0
var _dusk_on: bool = false
var _dusk_said: bool = false
var _clock_step: float = 0.0
var _ending: bool = false


func start(player: Player, world: WorldLevel, wagon: GustavWagon, town: TownManager) -> void:
	_player = player
	_world = world
	_town = town
	_wagon = wagon
	if wagon.gustav == null:
		wagon.set_open(true)
	_gustav = wagon.gustav
	var level: Node2D = wagon.get_parent() as Node2D
	_goal = _find_goal()
	_total = maxf(_gustav.global_position.distance_to(_goal), 1.0)
	_walker = CharacterBody2D.new()
	_walker.collision_layer = 0
	_walker.collision_mask = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	_walker.add_child(shape)
	_nav = EnemyNavigation.new()
	_walker.add_child(_nav)
	_walker.global_position = _gustav.global_position
	level.add_child(_walker)
	_nav.configure(_walker, shape, NAV, Callable(world, "navigation_floor"))
	_gustav.struck.connect(_on_struck)
	_player.health.died.connect(_on_player_down)
	_t0 = TimeManager.time_of_day
	_dusk_on = _t0 > 0.25 and _t0 < DUSK_AT - 0.01
	if _world.night != null:
		_world.night.story_hold = true
	_say("escort_start")


## The nearest lit ground on the line from the wagon to the town's door (a margin inside the light).
func _find_goal() -> Vector2:
	var door: Vector2 = _town.door_of(0)
	var from: Vector2 = _wagon.global_position + Vector2(40.0, 10.0)
	var length: float = from.distance_to(door)
	var steps: int = int(length / 8.0)
	for i: int in steps + 1:
		var point: Vector2 = from.lerp(door, float(i) / float(maxi(steps, 1)))
		if _town.light_depth(point) > 24.0:
			return point
	return door


func _exit_tree() -> void:
	if _world != null and is_instance_valid(_world) and _world.night != null:
		_world.night.story_hold = false
	if _walker != null and is_instance_valid(_walker):
		_walker.queue_free()


func _say(id: String) -> void:
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.play(id)


func _speaking() -> bool:
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	return box != null and box.is_speaking()


func _speed() -> float:
	return _player.max_speed * (Player.WOUND_SPEED if _player.wounded else 1.0) * 0.85


func _progress() -> float:
	return clampf(1.0 - _gustav.global_position.distance_to(_goal) / _total, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if _ending or not is_instance_valid(_player) or not is_instance_valid(_gustav):
		return
	for i: int in range(_alive.size() - 1, -1, -1):
		if not is_instance_valid(_alive[i]) or _alive[i].is_queued_for_deletion():
			_alive.remove_at(i)
	_dusk(delta)
	_waves()
	_gags_step(delta)
	if _gag_left > 0.0:
		_gag_left -= delta
		return
	var in_light: bool = _town.light_depth(_player.global_position) > 0.0
	var to_her: Vector2 = _player.global_position - _gustav.global_position
	if _town.light_depth(_gustav.global_position) > 14.0 and to_her.length() < 200.0:
		_arrive()
		return
	if in_light:
		_waiting = false
	elif _waiting and to_her.length() < GO_NEAR:
		_waiting = false
	elif not _waiting and to_her.length() > WAIT_FAR:
		_waiting = true
		_wait_time = 0.0
	if _waiting:
		_play("idle", to_her)
		_wait_time += delta
		if _wait_time > 7.0 and _wait_calls < WAITS.size() * 3 and not _speaking():
			_wait_time = 0.0
			_say(WAITS[_wait_calls % WAITS.size()])
			_wait_calls += 1
		return
	var target: Vector2 = _goal if in_light else _player.global_position
	if not in_light and to_her.length() < STOP_NEAR:
		_play("idle", to_her)
		return
	_steer(delta, target)


func _play(clip: String, toward: Vector2) -> void:
	if clip != _clip:
		_clip = clip
	_gustav.play(clip, toward)


func _steer(delta: float, target: Vector2) -> void:
	var at: Vector2 = _walker.global_position
	if _leg == Vector2.INF or at.distance_to(_leg) < 14.0:
		_leg = _next_leg(at, target)
		_nav.invalidate()
	var direction: Vector2 = _nav.direction_to(_leg, delta)
	_walker.velocity = direction * _speed()
	_walker.move_and_slide()
	_gustav.global_position = _walker.global_position
	if direction != Vector2.ZERO:
		_play("walk", direction)
	else:
		_play("idle", target - at)
	var left: float = _walker.global_position.distance_to(target)
	if left < _best - 8.0:
		_best = left
		_stuck = 0.0
	else:
		_stuck += delta
		if _stuck > 9.0:
			_unstick(target)


func _next_leg(from: Vector2, target: Vector2) -> Vector2:
	var to: Vector2 = target - from
	if to.length() <= LEGS and _nav.can_occupy(target):
		return target
	var dir: Vector2 = to.normalized()
	for fraction: float in [1.0, 0.65, 0.4]:
		for turn: float in [0.0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05]:
			var spot: Vector2 = from + dir.rotated(turn) * minf(LEGS * fraction, to.length())
			if _nav.can_occupy(spot):
				return spot
	return target


func _unstick(target: Vector2) -> void:
	_stuck = 0.0
	_best = INF
	_leg = Vector2.INF
	_nav.invalidate()
	var from: Vector2 = _walker.global_position
	var dir: Vector2 = (target - from).normalized()
	for reach: float in [90.0, 70.0, 50.0]:
		for turn: float in [0.0, 0.5, -0.5, 1.0, -1.0]:
			var spot: Vector2 = from + dir.rotated(turn) * reach
			if _nav.can_occupy(spot):
				_walker.global_position = spot
				_gustav.global_position = spot
				return


# ---------- the dusk ----------

## The clock runs towards 0.80 over the route (only if it is day when it starts); never backwards.
func _dusk(delta: float) -> void:
	if not _dusk_on:
		return
	_clock_step -= delta
	if _clock_step > 0.0:
		return
	_clock_step = 0.5
	var target: float = lerpf(_t0, DUSK_AT, clampf(_progress() / DUSK_BY, 0.0, 1.0))
	if target > TimeManager.time_of_day + 0.002:
		TimeManager.set_time(target)
	if not _dusk_said and TimeManager.time_of_day > 0.74 and not _speaking():
		_dusk_said = true
		_say("escort_dusk")


# ---------- the waves ----------

func _waves() -> void:
	if _wave_open:
		if _alive.is_empty():
			_wave_open = false
			if _wave == 2 and not _rested:
				_rest()
		return
	if _wave >= WAVES.size() or _town.light_depth(_player.global_position) > 0.0:
		return
	if _progress() < float(WAVES[_wave][0]) or _player.global_position.distance_to(_gustav.global_position) > 220.0 or _speaking():
		return
	var count: int = mini(int(WAVES[_wave][1]), MAX_ALIVE)
	var spots: Array[Vector2] = []
	for i: int in count:
		var spot: Vector2 = _wave_spot(i, count)
		if spot == Vector2.INF:
			return ## no free ground yet: try again next frame
		spots.append(spot)
	for spot: Vector2 in spots:
		var spider: ShadowSpider = _world.spawn_story_spider("shadow_spider", spot, (_gustav.global_position - spot).angle())
		if spider != null:
			_alive.append(spider)
	if _alive.is_empty():
		return
	_wave_open = true
	_say(String(WAVES[_wave][2]))
	_wave += 1


## A free spot of dark ground ahead of him (towards the goal), a little to the side for the second spider.
func _wave_spot(index: int, count: int) -> Vector2:
	var ahead: Vector2 = (_goal - _gustav.global_position).normalized()
	var side: float = 0.0 if count == 1 else (-0.55 if index == 0 else 0.55)
	for turn: float in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9]:
		for reach: float in [210.0, 180.0, 240.0]:
			var spot: Vector2 = _gustav.global_position + ahead.rotated(side + turn) * reach
			if _nav.can_occupy(spot) and _world.navigation_floor(spot) and _town.light_depth(spot) < -20.0:
				return spot
	return Vector2.INF


## The wave is beaten: after the second one she gets bread and berries when she is hurt.
func _rest() -> void:
	_rested = true
	if _player.health.current < _player.health.max_health * 0.7:
		_say("escort_rest")
		_player.health.heal(_player.health.max_health * 0.4)


func _on_player_down() -> void:
	for spider: ShadowSpider in _alive:
		if is_instance_valid(spider):
			spider.queue_free() ## the wave dissolves; it comes again when she is back with him
	_alive.clear()
	if _wave_open:
		_wave_open = false
		_wave = maxi(_wave - 1, 0)
	await get_tree().create_timer(6.0, true, false, true).timeout
	if not _ending:
		_say("escort_fell")


# ---------- the stumble and the hammer ----------

func _gags_step(delta: float) -> void:
	_gag_clock -= delta
	if _gag_clock > 0.0 or _gag_left > 0.0 or _alive.is_empty():
		return
	var nearest: ShadowSpider = null
	var best: float = 80.0
	for spider: ShadowSpider in _alive:
		var d: float = spider.global_position.distance_to(_gustav.global_position)
		if d < best:
			best = d
			nearest = spider
	if nearest == null:
		return
	_gag_clock = GAG_EVERY
	var toward: Vector2 = nearest.global_position - _gustav.global_position
	if _gags % 2 == 0:
		_say("escort_hit") ## he trips over his own feet and sits down hard
		_play("idle", toward)
		_gag_left = 0.7
	else:
		_say("escort_hammer")
		_play("work", toward)
		_gag_left = 1.1
	_gags += 1


func _on_struck() -> void:
	if _clip != "work":
		return
	var nearest: ShadowSpider = null
	var best: float = 90.0
	for spider: ShadowSpider in _alive:
		if not is_instance_valid(spider):
			continue
		var d: float = spider.global_position.distance_to(_gustav.global_position)
		if d < best:
			best = d
			nearest = spider
	if nearest != null:
		var health: HealthComponent = nearest.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.current > 0.0:
			health.take_damage(HAMMER_DAMAGE, _gustav.global_position, 30.0, 0)


# ---------- the end ----------

func _arrive() -> void:
	if _ending:
		return
	_ending = true
	_walker.velocity = Vector2.ZERO
	_play("idle", _player.global_position - _gustav.global_position)
	for spider: ShadowSpider in _alive:
		if is_instance_valid(spider):
			spider.queue_free()
	_alive.clear()
	if _speaking():
		await get_tree().create_timer(1.0, true, false, true).timeout
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		await box.play("escort_arrive")
	if is_instance_valid(_player) and _player.quests != null:
		_player.quests.set_flag("gustav_at_light")
	queue_free()
