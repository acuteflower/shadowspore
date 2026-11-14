class_name QuartzShard
extends Node2D
## Host-owned faceted sun-quartz spike fired by `QuartzGolem` (`SHARD_VOLLEY`).
## Sweeps its travelled segment, stops cleanly on world cover or relief changes, and shatters into crystal motes.

const HURTBOX_MASK: int = 1 << 5

var origin: Vector2
var direction: Vector2 = Vector2.RIGHT
var emission_point: Vector2 = Vector2.INF
var travelled: float = 0.0
var stopped: bool = false
var variant: int = 0
var damage_scale: float = 1.0
var _spec: Dictionary
var _age: float = 0.0
var _fade_age: float = 0.0
var _struck: Array[int] = []
var _glow: Node2D


func _ready() -> void:
	_spec = DataRegistry.get_entry("enemies", "quartz_golem")["shards"]
	direction = direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	if not emission_point.is_finite():
		emission_point = origin + Vector2(0.0, -14.0)
	global_position = origin + direction * travelled
	_glow = Node2D.new()
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	add_child(_glow)
	_glow.draw.connect(_draw_luminous)
	if not multiplayer.is_server():
		_request_snapshot.rpc_id(1)


static func clip_distance(node: Node2D, from: Vector2, dir: Vector2, length: float, radius: float) -> float:
	return ResonanceWave.clip_distance(node, from, dir, length, radius)


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
			var hit_any: bool = _sweep_damage(before, global_position)
			if hit_any or distance < requested - 0.01 or travelled >= float(_spec["range"]) - 0.01:
				_stop.rpc(travelled, 0.0)
		else:
			travelled = minf(float(_spec["range"]), travelled + requested)
			global_position = origin + direction * travelled
	queue_redraw()
	_glow.queue_redraw()


func _sweep_damage(from: Vector2, to: Vector2) -> bool:
	var hit_someone: bool = false
	var count: int = maxi(1, ceili(from.distance_to(to) / (float(_spec["radius"]) * 0.65)))
	for i: int in range(count + 1):
		var point: Vector2 = from.lerp(to, float(i) / float(count))
		for target: HurtboxComponent in HitScan.circle(self, point + Vector2(0.0, -12.0), float(_spec["radius"]), HURTBOX_MASK):
			if _struck.has(target.get_instance_id()):
				continue
			if Terrain.relief != null and absf(Terrain.relief.level_at(origin) - Terrain.relief.level_at(target.global_position)) >= 0.45:
				continue
			var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(point + Vector2(0.0, -4.0), target.global_position + Vector2(0.0, -4.0), 1)
			if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			_struck.append(target.get_instance_id())
			target.take_hit(roundf(float(_spec["damage"]) * damage_scale), origin + Vector2(0.0, -12.0), float(_spec["knockback"]))
			hit_someone = true
	return hit_someone


@rpc("authority", "call_local", "reliable")
func _stop(distance: float, fade: float) -> void:
	travelled = distance
	global_position = origin + direction * travelled
	stopped = true
	_fade_age = fade


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server():
		_snapshot.rpc_id(multiplayer.get_remote_sender_id(), travelled, stopped, _fade_age, variant)


@rpc("authority", "call_remote", "reliable")
func _snapshot(distance: float, ended: bool, fade: float, shard_variant: int) -> void:
	travelled = distance
	global_position = origin + direction * travelled
	stopped = ended
	_fade_age = fade
	variant = shard_variant


func _alpha() -> float:
	return 1.0 - clampf(_fade_age / float(_spec["fade_seconds"]), 0.0, 1.0) if stopped else 1.0


func _visual_at(distance: float) -> Vector2:
	var progress: float = clampf(distance / float(_spec["range"]), 0.0, 1.0)
	var shoulder_offset: Vector2 = emission_point - origin - Vector2(0.0, -12.0)
	return origin + direction * distance + Vector2(0.0, -12.0) + shoulder_offset * pow(1.0 - progress, 2.0)


func _draw() -> void:
	if _spec.is_empty():
		return
	var alpha: float = _alpha()
	var center: Vector2 = _visual_at(travelled) - global_position
	var across: Vector2 = direction.orthogonal()
	# Ground shadow directly beneath the flying quartz shard
	if not stopped:
		draw_rect(Rect2(Vector2(-3.0, -1.0), Vector2(6.0, 2.0)), Color("2b191d", 0.30 * alpha))

	var outline_c: Color = Color("34324c")
	var dark_c: Color = Color("7d96ba") if variant != 2 else Color("8b72ba")
	var mid_c: Color = Color("b8cbe4") if variant != 2 else Color("d8b2f8")
	var bright_c: Color = Color("dceaf8") if variant != 1 else Color("fff0c8")
	var spec_c: Color = Color("ffffff")

	if stopped:
		# Shatter burst of crisp faceted quartz splinters
		var burst_t: float = clampf(_fade_age / float(_spec["fade_seconds"]), 0.0, 1.0)
		for i: int in 7:
			var ang: float = direction.angle() + (float(i) - 3.0) * 0.58 + sin(float(i) * 3.1) * 0.25
			var spd: float = 12.0 + float((i * 7) % 11) * 1.8
			var p: Vector2 = (center + Vector2.from_angle(ang) * spd * burst_t + Vector2(0.0, 10.0 * burst_t * burst_t)).round()
			draw_rect(Rect2(p - Vector2.ONE, Vector2(3, 3)), Color(outline_c, alpha * 0.75))
			draw_rect(Rect2(p, Vector2(2 if i % 2 == 0 else 1, 1)), Color(spec_c if i % 2 == 0 else mid_c, alpha))
		return

	# Dual-helix turquoise-gold arcane ribbon + crystal dust motes trailing behind the spike
	var tail_len: float = minf(travelled, 34.0)
	var aura_trail_c: Color = Color("78f4e6") if variant == 0 else (Color("ffe488") if variant == 1 else Color("ff94e8"))
	for i: int in 12:
		var back: float = (float(i) + 1.0) * 2.7
		if back > tail_len:
			continue
		var fade: float = (1.0 - back / 35.0) * alpha
		var helix_a: float = sin(back * 0.42 - _age * 20.0) * 2.2
		var tp_a: Vector2 = (_visual_at(travelled - back) - global_position + across * helix_a).round()
		var tp_b: Vector2 = (_visual_at(travelled - back) - global_position - across * helix_a * 0.75).round()
		draw_rect(Rect2(tp_a, Vector2.ONE), Color(aura_trail_c, fade * 0.88))
		if i % 2 == 0:
			draw_rect(Rect2(tp_b, Vector2.ONE), Color("ffe488", fade * 0.80))

	# Pixel-snapped elongated faceted quartz spike (-7..+7 along flight axis) with glowing arcane core vein
	for s: int in range(-7, 8):
		var half_w: int = 2 if abs(s) <= 2 else (1 if abs(s) <= 5 else 0)
		for w: int in range(-half_w - 1, half_w + 2):
			var pt: Vector2 = (center + direction * float(s) + across * float(w)).round()
			if abs(w) > half_w or abs(s) == 7:
				draw_rect(Rect2(pt, Vector2.ONE), Color(outline_c, alpha))
			else:
				var c: Color = mid_c
				if w == 0 and abs(s) <= 4:
					c = spec_c if s >= 1 else aura_trail_c
				elif s >= 2 or (w <= 0 and s >= -1):
					c = spec_c if (s >= 4 and w == 0) else bright_c
				elif w > 0 or s <= -3:
					c = dark_c
				draw_rect(Rect2(pt, Vector2.ONE), Color(c, alpha))


func _draw_luminous() -> void:
	if _spec.is_empty():
		return
	var alpha: float = _alpha()
	var center: Vector2 = (_visual_at(travelled) - global_position).round()
	var aura_c: Color = Color("78f4e6") if variant == 0 else (Color("ffe488") if variant == 1 else Color("ff94e8"))
	if stopped:
		# Crisp 4-point arcane star flash on shatter
		var star_r: int = roundi(lerpf(6.0, 2.0, clampf(_fade_age / float(_spec["fade_seconds"]), 0.0, 1.0)))
		_glow.draw_rect(Rect2(center + Vector2(-star_r, 0), Vector2(star_r * 2 + 1, 1)), Color(aura_c, alpha * 0.85))
		_glow.draw_rect(Rect2(center + Vector2(0, -star_r), Vector2(1, star_r * 2 + 1)), Color("ffe488", alpha * 0.85))
		return
	_glow.draw_rect(Rect2(center - Vector2(6, 6), Vector2(13, 13)), Color(aura_c, alpha * 0.14))
	_glow.draw_rect(Rect2(center - Vector2(3, 3), Vector2(7, 7)), Color("ffe488", alpha * 0.28))
	for i: int in 5:
		var back: float = float(i + 1) * 5.2
		if back > travelled:
			continue
		var gp: Vector2 = (_visual_at(travelled - back) - global_position).round()
		var ga: float = alpha * (0.38 - float(i) * 0.065)
		_glow.draw_rect(Rect2(gp - Vector2.ONE, Vector2(3, 3)), Color(aura_c, ga))
		if i == 1 or i == 3:
			# Twinkling 4-point star glint in the shard's magical wake
			_glow.draw_rect(Rect2(gp + Vector2(-2, 0), Vector2(5, 1)), Color("ffffff", ga * 1.1))
			_glow.draw_rect(Rect2(gp + Vector2(0, -2), Vector2(1, 5)), Color("ffffff", ga * 1.1))
