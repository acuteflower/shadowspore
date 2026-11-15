class_name StarfallFx
extends Node2D
## Caelia's celestial right-click FX for `blade_starlight` (Sternenstich & Himmelsfall).
## Renders an additive unlit Astral Crescent wave and falling shooting stars descending from the sky.

const CYAN: Color = Color("78f4e6")
const AQUA_BRIGHT: Color = Color("d8fff9")
const GOLD: Color = Color("fff0b0")
const CORE: Color = Color("fffbe8")
const FALL_WINDOW: float = 0.22
const BURST_LIFE: float = 0.44

var _age: float = 0.0
var _life: float = 0.85
var _tip: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _crescent_len: float = 0.0
var _crescent_speed: float = 420.0
var _stars: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func spawn(
	parent: Node,
	tip: Vector2,
	dir: Vector2,
	crescent_len: float,
	crescent_speed: float,
	targets: PackedVector2Array,
	delays: PackedFloat32Array,
	star_radius: float
) -> void:
	if parent == null:
		return
	var fx: StarfallFx = StarfallFx.new()
	fx._tip = tip
	fx._dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	fx._crescent_len = crescent_len
	fx._crescent_speed = maxf(crescent_speed, 60.0)
	fx._rng.seed = hash(Vector2i(tip)) + targets.size() * 17
	var max_t: float = crescent_len / fx._crescent_speed + 0.28 if crescent_len > 0.0 else 0.0
	for i: int in targets.size():
		var hit_t: float = delays[i] if i < delays.size() else 0.18 + float(i) * 0.06
		var sky_offset: Vector2 = Vector2(fx._rng.randf_range(-42.0, -22.0), fx._rng.randf_range(-118.0, -96.0))
		fx._stars.append({
			"target": targets[i],
			"start": targets[i] + sky_offset,
			"hit_t": hit_t,
			"radius": star_radius,
			"gold": i % 2 == 0,
		})
		max_t = maxf(max_t, hit_t + BURST_LIFE)
	fx._life = max_t
	parent.add_child(fx)


func _ready() -> void:
	z_index = 7
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_age += delta / maxf(Engine.time_scale, 0.05)
	if _age >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _crescent_len > 0.0:
		_draw_crescent()
	for star: Dictionary in _stars:
		_draw_star(star)


func _draw_crescent() -> void:
	var travel_time: float = _crescent_len / _crescent_speed
	var p: float = clampf(_age / travel_time, 0.0, 1.0)
	var after: float = maxf(_age - travel_time, 0.0)
	var alpha: float = clampf(1.0 - after / 0.26, 0.0, 1.0)
	if alpha <= 0.01:
		return
	var head: Vector2 = _tip + _dir * (_crescent_len * (1.0 - pow(1.0 - p, 1.6)))
	var angle: float = _dir.angle()
	var span: float = deg_to_rad(56.0)
	var rad: float = 17.0 + 4.0 * p
	var arc_center: Vector2 = head - _dir * 10.0
	draw_arc(arc_center, rad, angle - span, angle + span, 14, Color(CYAN, alpha * 0.85), 3.0)
	draw_arc(arc_center, rad - 1.5, angle - span * 0.88, angle + span * 0.88, 12, Color(GOLD, alpha * 0.9), 1.6)
	draw_arc(arc_center, rad - 0.5, angle - span * 0.6, angle + span * 0.6, 10, Color(CORE, alpha), 1.0)
	for k: int in 6:
		var back_d: float = float(k + 1) * 9.0
		if back_d > _crescent_len * p:
			break
		var side: float = sin(float(k) * 2.1 + _age * 16.0) * 6.0
		var perp: Vector2 = Vector2(-_dir.y, _dir.x)
		var spark: Vector2 = (head - _dir * back_d + perp * side).round()
		var col: Color = GOLD if k % 2 == 0 else AQUA_BRIGHT
		draw_rect(Rect2(spark - Vector2.ONE, Vector2(2.0, 2.0)), Color(col, alpha * (1.0 - float(k) / 7.0)))


func _draw_star(star: Dictionary) -> void:
	var target: Vector2 = star["target"] as Vector2
	var start: Vector2 = star["start"] as Vector2
	var hit_t: float = float(star["hit_t"])
	var radius: float = float(star["radius"])
	var lead_gold: bool = bool(star["gold"])
	if _age < hit_t:
		var start_t: float = hit_t - FALL_WINDOW
		if _age < start_t:
			# Faint ground sigil telegraph just before descent
			var warn_a: float = clampf(0.28 * (_age / maxf(start_t, 0.01)), 0.0, 0.35)
			draw_arc(target, radius * 0.45, 0.0, TAU, 16, Color(CYAN, warn_a), 1.0)
			return
		var fall_k: float = clampf((_age - start_t) / FALL_WINDOW, 0.0, 1.0)
		var eased: float = fall_k * fall_k
		var head: Vector2 = start.lerp(target, eased)
		var tail: Vector2 = start.lerp(target, maxf(eased - 0.38, 0.0))
		draw_line(tail, head, Color(GOLD if lead_gold else CYAN, 0.75), 2.5)
		draw_line(tail.lerp(head, 0.4), head, Color(CORE, 0.95), 1.2)
		_draw_star_cross(head.round(), 4.0, CORE, 1.0)
		draw_arc(target, lerpf(radius * 0.65, 5.0, eased), 0.0, TAU, 18, Color(GOLD if lead_gold else CYAN, 0.45 + 0.35 * fall_k), 1.0)
		return
	var post: float = _age - hit_t
	var k: float = clampf(post / BURST_LIFE, 0.0, 1.0)
	var fade: float = 1.0 - k
	var ring_r: float = lerpf(4.0, radius, 1.0 - pow(1.0 - k, 2.2))
	draw_arc(target, ring_r, 0.0, TAU, 24, Color(CYAN, fade * 0.85), 2.2)
	draw_arc(target, ring_r * 0.68, 0.0, TAU, 18, Color(GOLD, fade * 0.9), 1.4)
	if post < 0.24:
		var flash_a: float = 1.0 - post / 0.24
		_draw_star_cross(target.round(), lerpf(3.0, 10.0, post / 0.24), CORE, flash_a)
	for i: int in 8:
		var a: float = float(i) * TAU / 8.0 + k * 0.6
		var pt: Vector2 = (target + Vector2.from_angle(a) * ring_r * 0.9 + Vector2(0.0, -post * 16.0)).round()
		var col: Color = GOLD if i % 2 == 0 else AQUA_BRIGHT
		draw_rect(Rect2(pt - Vector2(0.5, 0.5), Vector2(2.0, 2.0)), Color(col, fade * 0.9))


func _draw_star_cross(center: Vector2, arm: float, color: Color, alpha: float) -> void:
	draw_rect(Rect2(center - Vector2(arm, 0.5), Vector2(arm * 2.0 + 1.0, 1.5)), Color(color, alpha))
	draw_rect(Rect2(center - Vector2(0.5, arm), Vector2(1.5, arm * 2.0 + 1.0)), Color(color, alpha))
	draw_rect(Rect2(center - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), Color(CORE, alpha))
