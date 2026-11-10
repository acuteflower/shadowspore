class_name WallClimb
extends Node
## The owner asks to climb in a direction. The host selects the ledge, checks the
## corridor for the full player shape and confirms where the animation ends.

const SKILL: String = "wall_climb"
const REACH: float = 11.0 ## from the center of the feet collider
const MAX_SPAN: int = 58 ## a 32 px south face, the lip and room to stand
const LANDING_CLEARANCE: float = 9.0
const SECONDS: float = 1.55
const FRAMES: int = 32
const COLUMNS: int = 2 * FRAMES
const SHEET: Texture2D = preload("res://assets/characters/player_climb.png")
const BLOOD: Texture2D = preload("res://assets/characters/player_climb_blood.png")

var _player: Player
var _shape: CollisionShape2D
var _skills: SkillTreeComponent
var _prompt: InteractPrompt
var _elapsed: float = -1.0
var _start: Vector2
var _end: Vector2
var _direction: Vector2
var _sector: int
var _clip: int
var _motion: PackedVector2Array
var _depth_projection: Vector2
var _alignment: Vector2
var _walls: Array[RID] = []


func _ready() -> void:
	_player = get_parent() as Player
	_shape = _player.get_node("CollisionShape2D") as CollisionShape2D
	_skills = _player.get_node("SkillTreeComponent") as SkillTreeComponent
	if not multiplayer.is_server():
		_request_snapshot.rpc_id(1)


func active() -> bool:
	return _elapsed >= 0.0


func frame() -> Vector2i:
	return Vector2i(_clip * FRAMES + _frame_index(), _sector)


func _frame_index() -> int:
	return clampi(roundi(_elapsed / SECONDS * (FRAMES - 1)), 0, FRAMES - 1)


func sprite_offset() -> Vector2:
	var index: int = _frame_index()
	var t: float = float(index) / (FRAMES - 1)
	# Keep the correction constant while the hands are loaded so their baked
	# contacts stay fixed. Fit the actual wall as she reaches and steps away.
	var fit: float = 0.22 * smoothstep(0.0, 0.18, t) + 0.78 * smoothstep(0.78, 1.0, t)
	return _start + _project(_motion[index]) + _alignment * fit - _player.global_position


func _project(sample: Vector2) -> Vector2:
	return _depth_projection * sample.x + Vector2.UP * sample.y


func save_position() -> Vector2:
	return (_player.get_parent() as Node2D).to_local(_start) if active() else _player.position


func hide_prompt() -> void:
	if _prompt != null:
		_prompt.show_text("")


## Called after the normal interactable scan. A door or object keeps its usual E action.
func offer(direction: Vector2, pressed: bool) -> bool:
	var found: Vector2 = Vector2.INF
	if not InputManager.ui_blocking and not InputManager.freecam_open and _available():
		found = _landing(direction)
		if not found.is_finite() and absf(direction.x) > 0.25 and absf(direction.y) > 0.25:
			# A diagonal approach can slide along a wall. Try each axis still held.
			found = _landing(Vector2(signf(direction.x), 0.0))
			if not found.is_finite():
				found = _landing(Vector2(0.0, signf(direction.y)))
	if not found.is_finite():
		hide_prompt()
		return false
	if _prompt == null:
		_prompt = InteractPrompt.new()
		_prompt.position = Vector2(0.0, -51.0)
		_player.add_child(_prompt)
	_prompt.show_text("KLETTERN")
	if pressed:
		var heading: Vector2 = _player.global_position.direction_to(found)
		if multiplayer.is_server():
			_request(heading)
		else:
			_request.rpc_id(1, heading)
	return true


func _available() -> bool:
	return _skills.is_learned(SKILL) and _player.health.current > 0.0 and not _player.is_busy() and _player.launch_left <= 0.0 and not _player.fishing.rod_active()


func _landing(heading: Vector2) -> Vector2:
	var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
	var relief: Relief = Terrain.relief
	var start: Vector2 = _player.global_position
	if world == null or relief == null or heading.is_zero_approx() or not _outdoor_floor(world, start):
		return Vector2.INF
	var direction: Vector2 = heading.normalized()
	var foot_center: Vector2 = _shape.global_position
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(foot_center, foot_center + direction * REACH, _player.collision_mask, [_player.get_rid()])
	var hit: Dictionary = _player.get_world_2d().direct_space_state.intersect_ray(ray)
	var body: Node = hit.get("collider") as Node
	if body == null or not body.is_in_group("relief_walls"):
		return Vector2.INF
	var entry: Vector2 = hit["position"]
	var distance: float = foot_center.distance_to(entry) + 0.25
	if not relief.blocked_at(foot_center + direction * distance):
		return Vector2.INF
	# Stop at the far edge of this wall, even if another wall lies beyond it.
	while distance < MAX_SPAN and relief.blocked_at(foot_center + direction * distance):
		distance += 1.0
	for step: int in range(1, ceili(LANDING_CLEARANCE) + 1):
		if relief.blocked_at(foot_center + direction * (distance + float(step))):
			return Vector2.INF
	distance += LANDING_CLEARANCE
	if distance > MAX_SPAN:
		return Vector2.INF
	var end: Vector2 = start + direction * distance
	var low: float = relief.level_at(start)
	if not is_equal_approx(low, roundf(low)) or not is_equal_approx(relief.level_at(end), low + 1.0):
		return Vector2.INF
	for step: int in range(0, ceili(distance), 2):
		var point: Vector2 = start + direction * float(step)
		var level: float = relief.level_at(point)
		if not _outdoor_floor(world, point) or (not is_equal_approx(level, low) and not is_equal_approx(level, low + 1.0)):
			return Vector2.INF
	if not _outdoor_floor(world, end) or not _clear_at(start) or not _clear_at(end):
		return Vector2.INF
	return end if _clear_between(start, end, _wall_rids()) else Vector2.INF


func _outdoor_floor(world: WorldLevel, point: Vector2) -> bool:
	return Interiors.slot_at(point) < 0 and not MineManager.in_mine(point) and world.navigation_floor(point)


func _wall_rids() -> Array[RID]:
	var walls: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("relief_walls"):
		if node is StaticBody2D:
			walls.append((node as StaticBody2D).get_rid())
	return walls


func _query(at: Vector2, excluded: Array[RID] = []) -> PhysicsShapeQueryParameters2D:
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _shape.shape
	query.transform = Transform2D(_player.global_rotation, at) * _shape.transform
	query.collision_mask = _player.collision_mask
	var ignore: Array[RID] = excluded.duplicate()
	ignore.append(_player.get_rid())
	query.exclude = ignore
	return query


func _clear_at(at: Vector2) -> bool:
	return _player.get_world_2d().direct_space_state.intersect_shape(_query(at), 1).is_empty()


func _clear_between(from: Vector2, to: Vector2, excluded: Array[RID]) -> bool:
	var query: PhysicsShapeQueryParameters2D = _query(from, excluded)
	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.motion = to - from
	return space.cast_motion(query)[0] >= 0.9999


@rpc("any_peer", "call_remote", "reliable")
func _request(direction: Vector2) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or (sender != _player.get_multiplayer_authority() and not (sender == 0 and _player.is_multiplayer_authority())):
		return
	if not direction.is_finite() or not _available():
		return
	var end: Vector2 = _landing(direction)
	if end.is_finite():
		_walls = _wall_rids()
		_begin.rpc(_player.global_position, end, 0.0)


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server() and active():
		_begin.rpc_id(multiplayer.get_remote_sender_id(), _start, _end, _elapsed)


func _from_host() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	return sender == 1 or (sender == 0 and multiplayer.is_server())


@rpc("any_peer", "call_local", "reliable")
func _begin(from: Vector2, to: Vector2, elapsed: float) -> void:
	if not _from_host():
		return
	_start = from
	_end = to
	_direction = from.direction_to(to)
	_sector = posmod(roundi(_direction.angle() / (PI / 4.0)), 8)
	_clip = 1 if from.y - to.y > 30.0 else 0
	var rig: Dictionary = DataRegistry.table("wall_climb")
	var heading: Vector2 = Vector2.from_angle(_sector * PI / 4.0)
	_depth_projection = Vector2(heading.x, heading.y * float(rig["pitch_sine"]))
	_motion.clear()
	for sample: Array in (rig["clips"] as Array)[_clip]:
		_motion.append(Vector2(float(sample[0]), float(sample[1])))
	_alignment = to - from - _project(_motion[-1])
	_elapsed = elapsed
	_player.velocity = Vector2.ZERO
	_player.facing = _direction
	_player.sprinting = false
	_player.stealth.sneaking = false
	hide_prompt()


func step(delta: float) -> void:
	if _player.health.current <= 0.0 or _player.story_lock or _player.intro != null or _player.fainting or _player.stumbling or _player.launch_left > 0.0:
		interrupt()
		return
	var next: float = minf(_elapsed + delta, SECONDS)
	var point: Vector2 = _position_at(next)
	if multiplayer.is_server():
		var world: WorldLevel = get_tree().get_first_node_in_group("world") as WorldLevel
		if world == null or not _outdoor_floor(world, point) or not _outdoor_floor(world, _end) or not _clear_at(_end) or not _clear_between(_position_at(_elapsed), point, _walls):
			interrupt()
			return
		if next >= SECONDS:
			_finish.rpc(_end)
			return
	_elapsed = next
	_player.global_position = point
	_player.velocity = Vector2.ZERO


func _position_at(elapsed: float) -> Vector2:
	var frame_position: float = clampf(elapsed / SECONDS, 0.0, 1.0) * (FRAMES - 1)
	var index: int = mini(floori(frame_position), FRAMES - 2)
	var sample: Vector2 = _motion[index].lerp(_motion[index + 1], frame_position - index)
	var fraction: Vector2 = sample / _motion[-1]
	var progress: float = 0.4 * fraction.x + 0.6 * fraction.y
	return _start.lerp(_end, progress)


func interrupt() -> void:
	if multiplayer.is_server() and active():
		_finish.rpc(_start)


func before_teleport() -> void:
	interrupt()
	_elapsed = -1.0


@rpc("any_peer", "call_local", "reliable")
func _finish(at: Vector2) -> void:
	if not _from_host() or not active():
		return
	_elapsed = -1.0
	_walls.clear()
	_player.global_position = at
	_player.velocity = Vector2.ZERO
