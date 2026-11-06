class_name ResonanceWave
extends Node2D
## An independent host-owned travelling pressure front. Damage sweeps its whole
## travelled segment, stops at cover/height changes, and hits each player once.

const HURTBOX_MASK: int = 1 << 5
var origin: Vector2
var direction: Vector2 = Vector2.RIGHT
var emission_point: Vector2 = Vector2.INF
var travelled: float = 0.0
var stopped: bool = false
var damage_scale: float = 1.0 ## host only (the sweep is the host's): the shooter's scale
var _spec: Dictionary
var _age: float = 0.0
var _fade_age: float = 0.0
var _struck: Array[int] = []
var _glow: Node2D


func _ready() -> void:
	_spec = DataRegistry.get_entry("enemies", "void_listener")["wave"]
	direction = direction.normalized()
	if not emission_point.is_finite():
		emission_point = origin + Vector2(0, -12)
	global_position = origin + direction * travelled
	_glow = Node2D.new()
	var material: CanvasItemMaterial = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = material
	add_child(_glow)
	_glow.draw.connect(_draw_luminous)
	if not multiplayer.is_server():
		_request_snapshot.rpc_id(1)


static func clip_distance(node: Node2D, from: Vector2, dir: Vector2, length: float, radius: float) -> float:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, from + Vector2(0, -4))
	query.collision_mask = 1
	query.margin = 0.05
	var space: PhysicsDirectSpaceState2D = node.get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return 0.0
	query.motion = dir * length
	var cast: PackedFloat32Array = space.cast_motion(query)
	var result: float = length * cast[0]
	if Terrain.relief != null:
		var level: float = Terrain.relief.level_at(from)
		for i: int in range(1, ceili(result / 4.0) + 1):
			var distance: float = minf(float(i) * 4.0, result)
			if absf(Terrain.relief.level_at(from + dir * distance) - level) > 0.45:
				return maxf(0.0, distance - 4.0)
	return result


func _physics_process(delta: float) -> void:
	_age += delta
	if stopped:
		_fade_age += delta
		if multiplayer.is_server() and _fade_age >= float(_spec["fade_seconds"]):
			queue_free()
	else:
		var remaining: float = float(_spec["range"]) - travelled
		var requested: float = minf(float(_spec["speed"]) * delta, remaining)
		if multiplayer.is_server():
			var distance: float = clip_distance(self, global_position, direction, requested, float(_spec["radius"]))
			var before: Vector2 = global_position
			travelled += distance
			global_position = origin + direction * travelled
			_sweep_damage(before, global_position)
			if distance < requested - 0.01 or travelled >= float(_spec["range"]) - 0.01:
				_stop.rpc(travelled, 0.0)
		else:
			travelled = minf(float(_spec["range"]), travelled + requested)
			global_position = origin + direction * travelled
	queue_redraw()
	_glow.queue_redraw()


func _sweep_damage(from: Vector2, to: Vector2) -> void:
	var count: int = maxi(1, ceili(from.distance_to(to) / (float(_spec["radius"]) * 0.65)))
	for i: int in range(count + 1):
		var point: Vector2 = from.lerp(to, float(i) / count)
		for target: HurtboxComponent in HitScan.circle(self, point + Vector2(0, -12), float(_spec["radius"]), HURTBOX_MASK):
			if _struck.has(target.get_instance_id()):
				continue
			if Terrain.relief != null and absf(Terrain.relief.level_at(origin) - Terrain.relief.level_at(target.global_position)) >= 0.45:
				continue
			var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(point + Vector2(0, -4), target.global_position + Vector2(0, -4), 1)
			if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			_struck.append(target.get_instance_id())
			target.take_hit(roundf(float(_spec["damage"]) * damage_scale), origin + Vector2(0, -12), float(_spec["knockback"]))


@rpc("authority", "call_local", "reliable")
func _stop(distance: float, fade: float) -> void:
	travelled = distance
	global_position = origin + direction * travelled
	stopped = true
	_fade_age = fade


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server():
		_snapshot.rpc_id(multiplayer.get_remote_sender_id(), travelled, stopped, _fade_age)


@rpc("authority", "call_remote", "reliable")
func _snapshot(distance: float, ended: bool, fade: float) -> void:
	travelled = distance
	global_position = origin + direction * travelled
	stopped = ended
	_fade_age = fade


func _alpha() -> float:
	return 1.0 - clampf(_fade_age / float(_spec["fade_seconds"]), 0.0, 1.0) if stopped else 1.0


func _visual_at(distance: float) -> Vector2:
	# Preserve the exact visible throat at birth, then descend gently toward the
	# target's body plane. Gameplay still follows the announced ground corridor.
	var progress: float = clampf(distance / float(_spec["range"]), 0.0, 1.0)
	var mouth_offset: Vector2 = emission_point - origin - Vector2(0, -12)
	return origin + direction * distance + Vector2(0, -12) + mouth_offset * pow(1.0 - progress, 2.0)


func _trail_point(back: float) -> Vector2:
	var point: Vector2 = _visual_at(maxf(0.0, travelled - back)) - global_position
	return point + direction.orthogonal() * sin(back * 0.22 - _age * 15.0) * (back / 42.0) * 1.8


func _draw() -> void:
	if _spec.is_empty():
		return
	var alpha: float = _alpha()
	var tail: float = minf(travelled, 42.0)
	# A real ribbon of dark void tissue trails the white core. It tapers and
	# tears into separate shards instead of looking like a second glowing shot.
	for i: int in range(ceili(tail * 1.5), -1, -1):
		var back: float = float(i) / 1.5
		var fade: float = 1.0 - back / 46.0
		var size: float = 1.0 if back > 28.0 else (2.0 if back > 14.0 else 3.0)
		var point: Vector2 = _trail_point(back).round()
		draw_rect(Rect2(point - Vector2.ONE, Vector2.ONE * (size + 2)), Color("040208", alpha * fade))
		draw_rect(Rect2(point, Vector2.ONE * size), Color("1a1030", alpha * fade))
	for i: int in 14:
		var shed: float = floorf(travelled / 7.0) * 7.0 - i * 7.0
		if shed < 0.0:
			continue
		var age: float = (travelled - shed) / float(_spec["speed"]) + _fade_age
		if age > 0.42:
			continue
		var seed: float = sin(shed * 1.71) * 0.5 + 0.5
		var point: Vector2 = _visual_at(shed) - global_position + direction.orthogonal() * (seed - 0.5) * (3.0 + age * 42.0)
		point -= direction * age * 8.0
		draw_rect(Rect2(point.round(), Vector2.ONE * (2.0 if age < 0.2 else 1.0)), Color("0e0919", alpha * (1.0 - age / 0.42)))


func _draw_luminous() -> void:
	var alpha: float = _alpha()
	var across: Vector2 = direction.orthogonal()
	var center: Vector2 = _visual_at(travelled) - global_position
	var progress: float = clampf(travelled / float(_spec["range"]), 0.0, 1.0)
	var dissolve: float = smoothstep(0.28, 1.0, progress)
	# Pixel halos and a white elongated kernel, born inside the white throat.
	_glow.draw_rect(Rect2(center.round() - Vector2(5, 5), Vector2(11, 11)), Color("ecd2ff", alpha * (1.0 - dissolve * 0.7) * 0.055))
	_glow.draw_rect(Rect2(center.round() - Vector2(3, 3), Vector2(7, 7)), Color("ecd2ff", alpha * (1.0 - dissolve * 0.6) * 0.16))
	for x: int in range(-5, 5):
		for y: int in range(-3, 4):
			if pow(float(x) / 5.0, 2) + pow(float(y) / 3.0, 2) > 1.0:
				continue
			var noise: float = fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
			var point: Vector2 = center + direction * x + across * y
			if noise < dissolve * 0.68 and abs(x) + abs(y) > 1:
				continue
			var color: Color = Color("fff7ff").lerp(Color("8a4dff"), dissolve * (0.4 + noise * 0.6))
			_glow.draw_rect(Rect2(point.round(), Vector2.ONE), Color(color, alpha))
	for i: int in 22:
		var back: float = i * 2.0
		if back > travelled:
			break
		var point: Vector2 = _trail_point(back)
		var fade: float = 1.0 - back / 46.0
		_glow.draw_rect(Rect2(point.round(), Vector2.ONE), Color("8a4dff", alpha * fade * (0.25 + 0.2 * sin(back * 0.3 - _age * 12))))
	for i: int in 14:
		var shed: float = floorf(travelled / 7.0) * 7.0 - i * 7.0
		if shed < 0.0:
			continue
		var age: float = (travelled - shed) / float(_spec["speed"]) + _fade_age
		if age > 0.42:
			continue
		var seed: float = sin(shed * 1.71) * 0.5 + 0.5
		var point: Vector2 = _visual_at(shed) - global_position + across * (seed - 0.5) * (3.0 + age * 42.0) - direction * age * 8.0
		_glow.draw_rect(Rect2(point.round(), Vector2.ONE), Color("8a4dff", alpha * (1.0 - age / 0.42) * 0.55))
	# Small angular aftershocks expand at impact; they are cosmetic and fade quickly.
	if stopped:
		for arm: int in 5:
			var point: Vector2 = center + Vector2.from_angle(arm * TAU / 5.0) * (2.0 + _fade_age * 35.0)
			_glow.draw_rect(Rect2(point.round(), Vector2.ONE), Color("b06bff", alpha * 0.7))
