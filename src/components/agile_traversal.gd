class_name AgileTraversal
extends Node
## Host-authoritative agile obstacle `Vault` (over fallen logs, town fences, & `"vaultable"` props)
## and 1-level downward `Ledge Hop` across `Relief` cliff edges (`T6`, `V8`, `V12`).
## Mirrors the proven safety-corridor & late-join snapshot contract of `WallClimb`.

enum Kind { NONE = -1, VAULT = 0, HOP = 1 }

const VAULT_CLIP_START: int = 25
const VAULT_CLIP_FRAMES: int = 8
const HOP_CLIP_START: int = 33
const HOP_CLIP_FRAMES: int = 10
const LANDING_CLEARANCE: float = 8.5

var air_height: float = 0.0 ## Airborne vertical arc height in px (`> 0` lifts sprite & separates SunShadows!)

var _player: Player
var _shape: CollisionShape2D
var _prompt: InteractPrompt
var _kind: int = Kind.NONE
var _elapsed: float = -1.0
var _duration: float = 0.36
var _start: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.DOWN
var _sector: int = 2
var _jiggled: bool = false
var _land_fx_done: bool = false
var _hop_push_age: float = 0.0
var _vault_target_id: int = 0


func _ready() -> void:
	_player = get_parent() as Player
	_shape = _player.get_node("CollisionShape2D") as CollisionShape2D
	if not multiplayer.is_server() and NetworkManager.rpc_ready(self):
		_request_snapshot.rpc_id(1)


func active() -> bool:
	return _elapsed >= 0.0 and _kind != Kind.NONE


func kind() -> int:
	return _kind


func sector() -> int:
	return _sector


func frame_col() -> int:
	if _kind == Kind.VAULT:
		var u: float = clampf(_elapsed / maxf(_duration, 0.01), 0.0, 0.9999)
		return VAULT_CLIP_START + clampi(int(u * float(VAULT_CLIP_FRAMES)), 0, VAULT_CLIP_FRAMES - 1)
	if _kind == Kind.HOP:
		var u2: float = clampf(_elapsed / maxf(_duration, 0.01), 0.0, 0.9999)
		return HOP_CLIP_START + clampi(int(u2 * float(HOP_CLIP_FRAMES)), 0, HOP_CLIP_FRAMES - 1)
	return VAULT_CLIP_START


func hide_prompt() -> void:
	if _prompt != null:
		_prompt.show_text("")


func before_teleport() -> void:
	_reset_local()


func interrupt() -> void:
	if not active():
		return
	if multiplayer.is_server() and NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_abort.rpc(_start)
	else:
		_abort(_start)


func _reset_local() -> void:
	_elapsed = -1.0
	_kind = Kind.NONE
	air_height = 0.0
	_hop_push_age = 0.0
	hide_prompt()


## Offered right after `WallClimb.offer(...)` when no interactable or upward wall-climb claimed `E`.
## Supports intentional `E` vaulting over low props and `E` ledge-hopping down safe 1-level `Relief` edges.
func offer(direction: Vector2, pressed: bool, delta: float) -> bool:
	if InputManager.ui_blocking or InputManager.freecam_open or not _available():
		_hop_push_age = 0.0
		hide_prompt()
		return false

	var vault_info: Dictionary = _find_vault(direction)
	if bool(vault_info.get("ok", false)):
		_hop_push_age = 0.0
		_show_prompt("ÜBERSTEIGEN")
		if pressed:
			var end_v: Vector2 = vault_info["end"] as Vector2
			var heading: Vector2 = _player.global_position.direction_to(end_v)
			if multiplayer.is_server():
				_request(Kind.VAULT, heading)
			else:
				_request.rpc_id(1, Kind.VAULT, heading)
		return true

	var hop_end: Vector2 = _find_ledge_hop(direction)
	if not hop_end.is_finite() and absf(direction.x) > 0.25 and absf(direction.y) > 0.25:
		hop_end = _find_ledge_hop(Vector2(signf(direction.x), 0.0))
		if not hop_end.is_finite():
			hop_end = _find_ledge_hop(Vector2(0.0, signf(direction.y)))

	if hop_end.is_finite():
		var moving_toward: bool = InputManager.move_vector().dot(_player.global_position.direction_to(hop_end)) > 0.35
		_hop_push_age = (_hop_push_age + delta) if moving_toward else maxf(_hop_push_age - delta * 2.0, 0.0)
		_show_prompt("HINUNTERSPRINGEN")
		if pressed:
			var hop_dir: Vector2 = _player.global_position.direction_to(hop_end)
			if multiplayer.is_server():
				_request(Kind.HOP, hop_dir)
			else:
				_request.rpc_id(1, Kind.HOP, hop_dir)
		return true

	_hop_push_age = 0.0
	hide_prompt()
	return false


func _show_prompt(label: String) -> void:
	if _prompt == null:
		_prompt = InteractPrompt.new()
		_prompt.position = Vector2(0.0, -51.0)
		_player.add_child(_prompt)
	_prompt.show_text(label)


func _available() -> bool:
	if _player == null or active():
		return false
	return (
		_player.health.current > 0.0
		and not _player.is_busy()
		and _player.carry_stone == 0
		and _player.launch_left <= 0.0
		and (_player.fishing == null or not _player.fishing.rod_active())
	)


static func _is_vaultable_collider(collider: Object) -> Node2D:
	if collider == null or not (collider is Node):
		return null
	var node: Node = collider as Node
	if node.is_in_group("vaultable") and node is Node2D:
		return node as Node2D
	var p: Node = node.get_parent()
	if p != null:
		if p is FallenLog and not (p as FallenLog).is_depleted():
			return p as Node2D
		if p is TownStructure and (p as TownStructure).piece == "fence" and (p as TownStructure).progress >= 1000:
			return p as Node2D
		if p.is_in_group("vaultable") and p is Node2D:
			return p as Node2D
	return null


func _find_vault(heading: Vector2) -> Dictionary:
	if heading.is_zero_approx() or _shape == null:
		return {"ok": false}
	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	if space == null:
		return {"ok": false}
	var cfg: Dictionary = MovementRules.section("agile")
	var reach: float = float(cfg.get("vault_reach", 15.0))
	var max_span: float = float(cfg.get("vault_max_span", 28.0))
	var dir: Vector2 = heading.normalized()
	var foot_center: Vector2 = _shape.global_position
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(foot_center, foot_center + dir * reach, 1, [_player.get_rid()])
	var hit: Dictionary = space.intersect_ray(ray)
	if hit.is_empty():
		return {"ok": false}
	var prop: Node2D = _is_vaultable_collider(hit.get("collider"))
	if prop == null:
		return {"ok": false}

	var start: Vector2 = _player.global_position
	var hit_dist: float = foot_center.distance_to(hit["position"] as Vector2)
	# Probe past the thin obstacle (`+8..max_span px`) for the first clear landing spot on the same ground level
	for step_px: int in range(int(hit_dist) + 9, int(max_span) + 1, 2):
		var cand: Vector2 = start + dir * float(step_px)
		if not _same_floor_ok(start, cand):
			continue
		if _clear_at(cand):
			return {"ok": true, "end": cand, "target_id": prop.get_instance_id()}
	return {"ok": false}


func _same_floor_ok(start: Vector2, cand: Vector2) -> bool:
	if Interiors.slot_at(start) >= 0 or MineManager.in_mine(start):
		return false
	var world: Node = get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("navigation_floor") and not bool(world.call("navigation_floor", cand)):
		return false
	var relief: Relief = Terrain.relief
	if relief != null:
		if relief.blocked_at(cand):
			return false
		if absf(relief.level_at(cand) - relief.level_at(start)) > 0.25:
			return false
	return true


func _find_ledge_hop(heading: Vector2) -> Vector2:
	var world: Node = get_tree().get_first_node_in_group("world")
	var relief: Relief = Terrain.relief
	var start: Vector2 = _player.global_position
	if relief == null or heading.is_zero_approx() or _shape == null:
		return Vector2.INF
	if Interiors.slot_at(start) >= 0 or MineManager.in_mine(start):
		return Vector2.INF
	if world != null and world.has_method("navigation_floor") and not bool(world.call("navigation_floor", start)):
		return Vector2.INF

	var cfg: Dictionary = MovementRules.section("agile")
	var reach: float = float(cfg.get("hop_reach", 13.0))
	var max_span: int = int(cfg.get("hop_max_span", 46.0))
	var dir: Vector2 = heading.normalized()
	var foot_center: Vector2 = _shape.global_position
	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	if space == null:
		return Vector2.INF

	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(foot_center, foot_center + dir * reach, _player.collision_mask, [_player.get_rid()])
	var hit: Dictionary = space.intersect_ray(ray)
	var body: Node = hit.get("collider") as Node
	if body == null or not body.is_in_group("relief_walls"):
		return Vector2.INF

	var distance: float = foot_center.distance_to(hit["position"] as Vector2) + 0.5
	if not relief.blocked_at(foot_center + dir * distance):
		return Vector2.INF
	while distance < float(max_span) and relief.blocked_at(foot_center + dir * distance):
		distance += 1.0
	for step_i: int in range(1, ceili(LANDING_CLEARANCE) + 1):
		if relief.blocked_at(foot_center + dir * (distance + float(step_i))):
			return Vector2.INF
	distance += LANDING_CLEARANCE
	if distance > float(max_span):
		return Vector2.INF

	var end: Vector2 = start + dir * distance
	var high: float = relief.level_at(start)
	if not is_equal_approx(high, roundf(high)) or not is_equal_approx(relief.level_at(end), high - 1.0):
		return Vector2.INF
	if world != null and world.has_method("navigation_floor") and not bool(world.call("navigation_floor", end)):
		return Vector2.INF
	# Refuse hopping directly into deep swimming water or onto solid props
	var end_surf: Dictionary = Terrain.surface_data(Terrain.surface_at(end))
	if float(end_surf.get("submerge", 0.0)) > 4.0:
		return Vector2.INF
	if not _clear_at(end):
		return Vector2.INF
	for blocker: Node in get_tree().get_nodes_in_group("climb_block"):
		if bool(blocker.call("blocks_climb", start, end)):
			return Vector2.INF
	return end


func _clear_at(at: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	if space == null or _shape == null:
		return false
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _shape.shape
	query.transform = Transform2D(_player.global_rotation, at) * _shape.transform
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()


@rpc("any_peer", "call_remote", "reliable")
func _request(req_kind: int, direction: Vector2) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or (sender != _player.get_multiplayer_authority() and not (sender == 0 and _player.is_multiplayer_authority())):
		return
	if not direction.is_finite() or not _available():
		return
	if req_kind == Kind.VAULT:
		var v: Dictionary = _find_vault(direction)
		if bool(v.get("ok", false)):
			_begin.rpc(Kind.VAULT, _player.global_position, v["end"] as Vector2, 0.0, int(v.get("target_id", 0)))
	elif req_kind == Kind.HOP:
		var hop_end: Vector2 = _find_ledge_hop(direction)
		if hop_end.is_finite():
			_begin.rpc(Kind.HOP, _player.global_position, hop_end, 0.0, 0)


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server() and active():
		_begin.rpc_id(multiplayer.get_remote_sender_id(), _kind, _start, _end, _elapsed, _vault_target_id)


func _from_host() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	return sender == 1 or (sender == 0 and multiplayer.is_server())


@rpc("any_peer", "call_local", "reliable")
func _begin(move_kind: int, from: Vector2, to: Vector2, elapsed: float, target_id: int) -> void:
	if not _from_host():
		return
	var cfg: Dictionary = MovementRules.section("agile")
	_kind = move_kind
	_start = from
	_end = to
	_direction = from.direction_to(to)
	if _direction.is_zero_approx():
		_direction = Vector2.DOWN
	_sector = posmod(roundi(_direction.angle() / (PI / 4.0)), 8)
	_duration = float(cfg.get("vault_seconds", 0.36) if move_kind == Kind.VAULT else cfg.get("hop_seconds", 0.42))
	_elapsed = elapsed
	_jiggled = false
	_land_fx_done = false
	_vault_target_id = target_id
	air_height = 0.0
	_player.facing = _direction
	_player.stealth.sneaking = false
	hide_prompt()


func step(delta: float) -> void:
	if not active():
		return
	if _player.health.current <= 0.0 or _player.story_lock or _player.intro != null or _player.fainting or _player.stumbling or _player.launch_left > 0.0:
		interrupt()
		return

	var next_t: float = minf(_elapsed + delta, _duration)
	var u: float = clampf(next_t / maxf(_duration, 0.01), 0.0, 1.0)
	var cfg: Dictionary = MovementRules.section("agile")

	if _kind == Kind.VAULT:
		var smooth_u: float = smoothstep(0.0, 1.0, u)
		_player.global_position = _start.lerp(_end, smooth_u)
		var arc_u: float = clampf((u - 0.14) / 0.64, 0.0, 1.0)
		air_height = sin(arc_u * PI) * float(cfg.get("vault_arc_px", 8.5))
		if not _jiggled and u >= 0.26 and _vault_target_id != 0:
			_jiggled = true
			var obj: Object = instance_from_id(_vault_target_id)
			if obj is FallenLog:
				(obj as FallenLog)._jiggle(0.28)
		if not _land_fx_done and u >= 0.78:
			_land_fx_done = true
			_player._on_agile_touchdown(_end, _direction, false)
	else:
		# Ledge Hop: push off cliff lip (0..0.14), parabolic drop (0.14..0.68), cushioned knee-sink settle (0.68..1.0)
		var travel_u: float = clampf(u / 0.72, 0.0, 1.0)
		var eased_travel: float = travel_u * travel_u * (3.0 - 2.0 * travel_u)
		_player.global_position = _start.lerp(_end, eased_travel)
		var hop_u: float = clampf((u - 0.12) / 0.56, 0.0, 1.0)
		air_height = sin(hop_u * PI) * float(cfg.get("hop_arc_px", 7.0))
		if not _land_fx_done and u >= 0.68:
			_land_fx_done = true
			_player._on_agile_touchdown(_end, _direction, true)

	_elapsed = next_t
	_player.velocity = Vector2.ZERO

	if multiplayer.is_server() and next_t >= _duration:
		var was_vault: bool = _kind == Kind.VAULT
		if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
			_finish.rpc(_end, was_vault)
		else:
			_finish(_end, was_vault)


@rpc("any_peer", "call_local", "reliable")
func _finish(at: Vector2, was_vault: bool) -> void:
	if not _from_host():
		return
	var carry_dir: Vector2 = _direction
	_reset_local()
	_player.global_position = at
	if _player.is_multiplayer_authority():
		var held: Vector2 = InputManager.move_vector()
		if held.length_squared() > 0.01:
			var keep_spd: float = _player.sprint_speed if (was_vault and InputManager.sprint_held()) else _player.max_speed
			_player.velocity = held.normalized() * keep_spd
			_player.facing = held.normalized()
		else:
			_player.velocity = carry_dir * (38.0 if was_vault else 0.0)


@rpc("any_peer", "call_local", "reliable")
func _abort(at: Vector2) -> void:
	if not _from_host():
		return
	_reset_local()
	_player.global_position = at
	_player.velocity = Vector2.ZERO
