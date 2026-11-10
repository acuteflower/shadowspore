class_name WildRabbit
extends CharacterBody2D
## Peaceful ambient wildlife. The host senses threats and chooses every hop; reliable packets
## animate the same complete hop on all peers. Ground collision applies even while visually airborne.

enum State { REST, GRAZE, WANDER, ALERT, FLEE, RECOVER, GROOM }

const SHEET_COLUMNS: int = 26
const DIRECTIONS: int = 8

var appearance: int = 0
var home: Vector2 = Vector2.ZERO
var temperament: float = 1.0
var facing: float = 0.0
var ambient_event: bool = false
var captured: bool = false
var state: State = State.REST
var _spec: Dictionary
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _state_time: float = 0.0
var _state_duration: float = 2.0
var _sense_left: float = 0.0
var _safe_time: float = 0.0
var _threat: Vector2 = Vector2.ZERO
var _has_threat: bool = false
var _hops_left: int = 0
var _pause_left: float = 0.0
var _wander_dir: Vector2 = Vector2.RIGHT
var _hopping: bool = false
var _hop_time: float = 0.0
var _hop_duration: float = 0.5
var _hop_start: Vector2
var _hop_end: Vector2
var _hop_height: float = 4.0
var _was_hopping: bool = false
var _shadow: Node2D
var _nearby_herd: Array[Vector2] = []
var _nearby_herd_left: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D


var _thump_cool: float = 0.0

func _ready() -> void:
	add_to_group("wild_animals") ## the cursor shrinks to a dot over animals (GameCursor)
	_spec = DataRegistry.get_entry("wildlife", "rabbit")
	_rng.seed = hash(name) + int(home.x) * 31 + int(home.y) * 7
	add_to_group("wildlife")
	_shadow = Node2D.new()
	_shadow.show_behind_parent = true
	_shadow.draw.connect(_draw_shadow)
	add_child(_shadow)
	if multiplayer.is_server():
		_state_duration = _range("rest_seconds")
		_sense_left = _rng.randf_range(0.0, float(_spec["sense_interval"]))
	else:
		_request_snapshot.rpc_id(1)


func _physics_process(delta: float) -> void:
	if captured: return
	_state_time += delta
	_pause_left -= delta
	if multiplayer.is_server():
		_nearby_herd_left = maxf(0.0, _nearby_herd_left - delta)
		_sense_left -= delta
		if _sense_left <= 0.0:
			_sense_left = float(_spec["sense_interval"])
			_sense()
		if state == State.FLEE:
			_safe_time = 0.0 if _has_threat else _safe_time + delta
		if not _hopping and (not ambient_event or _has_threat):
			_think()
	if _hopping:
		_advance_hop(delta)


func _process(_delta: float) -> void:
	if captured: return
	var col: int = 0
	if _hopping:
		var t: float = clampf(_hop_time / _hop_duration, 0.0, 1.0)
		col = 14 + mini(5, int(t * 6.0))
		_sprite.position.y = -roundf(sin(_travel(t) * PI) * _hop_height)
	else:
		_sprite.position.y = 0.0
		match state:
			State.GRAZE:
				col = 4 + int(_state_time * 5.0) % 6
			State.ALERT, State.RECOVER, State.FLEE:
				col = 10 + int(_state_time * 3.0) % 4
			State.GROOM:
				col = 20 + int(_state_time * 5.0) % 6
			_:
				col = int(_state_time * 3.0) % 4
	var sector: int = posmod(roundi(facing / (PI / 4.0)), DIRECTIONS)
	_sprite.frame = (clampi(appearance, 0, 5) * DIRECTIONS + sector) * SHEET_COLUMNS + col
	if _hopping or _was_hopping:
		_shadow.queue_redraw()
	_was_hopping = _hopping


func _draw_shadow() -> void:
	var t: float = clampf(_hop_time / _hop_duration, 0.0, 1.0) if _hopping else 0.0
	var air: float = sin(_travel(t) * PI)
	_shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 - air * 0.18, 1.0))
	_shadow.draw_style_box(_shadow_style(), Rect2(-6, -2, 12, 4))


static var _shadow_box: StyleBoxFlat
static func _shadow_style() -> StyleBoxFlat:
	if _shadow_box == null:
		_shadow_box = StyleBoxFlat.new()
		_shadow_box.bg_color = Color(0.04, 0.025, 0.07, 0.25)
		_shadow_box.set_corner_radius_all(2)
	return _shadow_box


func _range(key: String) -> float:
	var bounds: Array = _spec[key]
	return _rng.randf_range(float(bounds[0]), float(bounds[1]))


## Every nearby player matters. Slow approach produces a watchful freeze; sprint/weapon noise
## triggers flight earlier. Enemy silhouettes are frightening too. No player input is read here.
func _sense() -> void:
	_has_threat = false
	var closest: float = INF
	var flee_now: bool = false
	var candidates: Array[Node] = []
	candidates.append_array(Player.all)
	candidates.append_array(get_tree().get_nodes_in_group("predators"))
	candidates.append_array(get_tree().get_nodes_in_group("wildlife_hunters"))
	for candidate: Node in candidates:
		var actor: Node2D = candidate as Node2D
		if actor == null:
			continue
		var alert_range: float = float(_spec["alert_range"]) * temperament
		var flee_range: float = float(_spec["flee_range"]) * temperament
		var release: float = float(_spec["safe_range"]) * temperament
		var noisy: bool = false
		if actor is Player:
			var player: Player = actor as Player
			if player.health.current <= 0.0:
				continue
			var calm: float = TownManager.calm_at(get_tree(), global_position) ## used to the town's people
			alert_range *= calm
			flee_range *= calm
			if player.stealth.sneaking:
				alert_range *= float(_spec["sneak_multiplier"])
				flee_range *= float(_spec["sneak_multiplier"])
			if player.sprinting:
				alert_range *= float(_spec["sprint_alert_multiplier"])
				flee_range *= float(_spec["sprint_flee_multiplier"])
				noisy = true
			if player.attack.is_swinging() and global_position.distance_to(player.global_position) < float(_spec["swing_scare_range"]) * player.attack.noise_scale():
				noisy = true
				flee_now = true
		else:
			var health: HealthComponent = actor.get_node_or_null("HealthComponent") as HealthComponent
			if health != null and health.current <= 0.0:
				continue
			alert_range *= float(_spec["predator_multiplier"])
			flee_range *= float(_spec["predator_multiplier"])
			release *= float(_spec["predator_multiplier"])
		var distance: float = global_position.distance_to(actor.global_position)
		var radius: float = release if state == State.FLEE else alert_range
		if distance > radius:
			continue
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, actor.global_position, 1)
		if not noisy and not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		_has_threat = true
		flee_now = flee_now or distance < flee_range
		if distance < closest:
			closest = distance
			_threat = actor.global_position
	if flee_now and _has_threat:
		if state != State.FLEE:
			_set_state(State.FLEE, 0.0)
			_alarm_neighbours()
	elif _has_threat and state not in [State.FLEE, State.ALERT]:
		_set_state(State.ALERT, float(_spec["alert_seconds"]))
	if _has_threat and state == State.ALERT and not _hopping:
		facing = (_threat - global_position).angle()


func _alarm_neighbours() -> void:
	for node: Node in get_tree().get_nodes_in_group("wildlife"):
		var other: WildRabbit = node as WildRabbit
		if other != null and other != self and other.state not in [State.FLEE, State.ALERT] and global_position.distance_to(other.global_position) < float(_spec["alarm_range"]):
			other._threat = _threat
			other._set_state(State.ALERT, float(_spec["alert_seconds"]))


func _think() -> void:
	match state:
		State.FLEE:
			if _safe_time >= float(_spec["calm_seconds"]):
				_set_state(State.RECOVER, float(_spec["recover_seconds"]))
			elif _pause_left <= 0.0:
				_try_hop((global_position - _threat).normalized(), true)
		State.ALERT:
			if _state_time >= _state_duration and not _has_threat:
				_set_state(State.RECOVER, float(_spec["recover_seconds"]))
		State.WANDER:
			if _hops_left <= 0:
				_choose_idle()
			elif _pause_left <= 0.0:
				_try_hop(_wander_dir, false)
		_:
			if _state_time >= _state_duration:
				if _rng.randf() < 0.42:
					_wander_dir = Vector2.from_angle(_rng.randf() * TAU)
					if global_position.distance_to(home) > float(_spec["home_radius"]):
						_wander_dir = (home - global_position).normalized()
					_hops_left = _rng.randi_range(int(_spec["wander_hops"][0]), int(_spec["wander_hops"][1]))
					_set_state(State.WANDER, 0.0)
				else:
					_choose_idle()


func _choose_idle() -> void:
	var roll: float = _rng.randf()
	if roll < 0.55:
		_set_state(State.GRAZE, _range("graze_seconds"))
	elif roll < 0.72:
		_set_state(State.GROOM, _range("groom_seconds"))
	else:
		_set_state(State.REST, _range("rest_seconds"))


func _set_state(next: State, duration: float) -> void:
	_set_mood.rpc(next, duration, facing)


@rpc("authority", "call_local", "reliable")
func _set_mood(next: int, duration: float, direction: float) -> void:
	state = next as State
	_state_time = 0.0
	_state_duration = duration
	facing = direction
	if state == State.FLEE:
		_safe_time = 0.0
		_pause_left = 0.0


func _try_hop(direction: Vector2, fleeing: bool) -> void:
	if direction == Vector2.ZERO:
		direction = Vector2.from_angle(_rng.randf() * TAU)
	var distance: float = _range("flee_distance" if fleeing else "wander_distance")
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	if _nearby_herd_left <= 0.0 or _nearby_herd.is_empty():
		_nearby_herd_left = 0.5
		_nearby_herd.clear()
		var max_dist_sq: float = (distance + 20.0) * (distance + 20.0)
		for node: Node in get_tree().get_nodes_in_group("wildlife"):
			if node != self and node is Node2D:
				var pos: Vector2 = (node as Node2D).global_position
				if global_position.distance_squared_to(pos) <= max_dist_sq:
					_nearby_herd.append(pos)
	for angle: float in [0.0, 0.6, -0.6, PI]:
		var step: Vector2 = direction.rotated(angle) * distance
		var end: Vector2 = global_position + step
		if test_move(global_transform, step) or not _ground_safe(end) or not _ground_safe(global_position + step * 0.5):
			continue
		var score: float = -absf(angle) * 8.0
		if fleeing:
			score += end.distance_to(_threat)
		for neighbour_pos: Vector2 in _nearby_herd:
			var gap: float = end.distance_to(neighbour_pos)
			if gap < 15.0:
				score -= (15.0 - gap) * 2.0
		if score > best_score:
			best = end
			best_score = score
	if best_score == -INF:
		_pause_left = float(_spec["blocked_pause"])
		if not fleeing:
			_hops_left -= 1
		return
	_begin_hop.rpc(global_position, best, _range("flee_duration" if fleeing else "wander_duration"), float(_spec["flee_height"] if fleeing else _spec["wander_height"]), 0.0)
	_hops_left -= 1


func _ground_safe(point: Vector2) -> bool:
	if Terrain.relief != null and not Terrain.relief.flat_around(point, 3.0):
		return false
	return float(Terrain.surface_data(Terrain.surface_at(point)).get("submerge", 0.0)) <= 0.0


@rpc("authority", "call_local", "reliable")
func _begin_hop(start: Vector2, end: Vector2, duration: float, height: float, elapsed: float) -> void:
	_hop_start = start
	_hop_end = end
	_hop_duration = maxf(0.1, duration)
	_hop_height = height
	_hop_time = elapsed
	_hopping = true
	if state == State.FLEE and elapsed < 0.05 and Time.get_ticks_msec() * 0.001 > _thump_cool and randf() < 0.3:
		_thump_cool = Time.get_ticks_msec() * 0.001 + 8.0
		Sfx.at(self, "rabbit_thump", start, -6.0, 0.06, 240.0)
	facing = (end - start).angle()


static func _travel(t: float) -> float:
	return smoothstep(0.15, 0.85, t)


func _advance_hop(delta: float) -> void:
	_hop_time = minf(_hop_duration, _hop_time + delta)
	var next: Vector2 = _hop_start.lerp(_hop_end, _travel(_hop_time / _hop_duration))
	if multiplayer.is_server():
		var hit: KinematicCollision2D = move_and_collide(next - global_position)
		if hit != null or _hop_time >= _hop_duration:
			_land.rpc(global_position)
			_pause_left = _range("flee_pause" if state == State.FLEE else "wander_pause")
	else:
		global_position = next
		if _hop_time >= _hop_duration:
			_hopping = false


@rpc("authority", "call_local", "reliable")
func _land(at: Vector2) -> void:
	global_position = at
	_hopping = false


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server():
		_receive_snapshot.rpc_id(multiplayer.get_remote_sender_id(), state, _state_duration, _state_time, facing, global_position, _hopping, _hop_start, _hop_end, _hop_duration, _hop_height, _hop_time)


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(mood: int, duration: float, elapsed: float, direction: float, at: Vector2, hopping: bool, start: Vector2, end: Vector2, hop_seconds: float, height: float, hop_elapsed: float) -> void:
	_set_mood(mood, duration, direction)
	_state_time = elapsed
	global_position = at
	if hopping:
		_begin_hop(start, end, hop_seconds, height, hop_elapsed)
	else:
		_hopping = false


## Natural predation, host-owned and replicated. No player rewards or gore.
func caught_by_predator() -> void:
	if not multiplayer.is_server() or captured: return
	_caught.rpc()
	await get_tree().create_timer(0.3).timeout
	if is_inside_tree(): queue_free()

@rpc("authority","call_local","reliable")
func _caught() -> void:
	captured = true
	ambient_event = false
	_hopping = false
	_shadow.visible = false
	create_tween().tween_property(_sprite,"modulate:a",0.0,0.25)
