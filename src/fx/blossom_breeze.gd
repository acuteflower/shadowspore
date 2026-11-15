class_name BlossomBreeze
extends Node2D
## Legendary seasonal aura for Ellie's Spring 2027 Qipao (`perlenbluete` — "Perlenblüte"):
## delicate pixel-art lotus and sakura petals drift from her split silk skirt hem as she walks,
## sprints, or shadow-steps, with an occasional solitary petal carried by the spring breeze at rest.

const MAX_PETALS: int = 44
const OUTFIT_STYLE: String = "perlenbluete"

const COL_PEARL: Color = Color("fffbf4")
const COL_PEARL_SHADE: Color = Color("dfd6e4")
const COL_BLUSH: Color = Color("f6bac6")
const COL_BLUSH_SHADE: Color = Color("d8869c")
const COL_ICE: Color = Color("9ce6f2")
const COL_ICE_SHADE: Color = Color("62b0c8")
const COL_GOLD: Color = Color("f0d07a")

var _petals: Array[Dictionary] = []
var _emit_accum: float = 0.0
var _idle_wait: float = 1.1
var _was_stepping: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 1
	material = Unlit.material()
	_rng.randomize()


func _process(delta: float) -> void:
	var body: CharacterBody2D = get_parent() as CharacterBody2D
	if body == null:
		return
	var app: AppearanceComponent = body.get_node_or_null("AppearanceComponent") as AppearanceComponent
	var active: bool = _is_outfit_active(body, app)
	var step_val: float = float(body.get("_step_t"))
	var stepping_now: bool = step_val >= 0.0
	if active and stepping_now and not _was_stepping:
		_spawn_step_burst(body, app)
	_was_stepping = stepping_now

	if not active and _petals.is_empty():
		return

	if active:
		var speed: float = body.velocity.length()
		if speed > 14.0:
			var rate: float = lerpf(4.8, 15.5, clampf((speed - 20.0) / 110.0, 0.0, 1.0))
			_emit_accum += delta * rate
			while _emit_accum >= 1.0:
				_emit_accum -= 1.0
				_spawn_petal(body, app, false)
		else:
			_idle_wait -= delta
			if _idle_wait <= 0.0:
				_idle_wait = _rng.randf_range(1.55, 2.55)
				_spawn_petal(body, app, true)

	if _petals.is_empty():
		return

	var i: int = _petals.size() - 1
	while i >= 0:
		var p: Dictionary = _petals[i]
		var age: float = float(p["age"]) + delta
		var life: float = float(p["life"])
		if age >= life:
			_petals.remove_at(i)
		else:
			p["age"] = age
			var vel: Vector2 = p["vel"] as Vector2
			vel = vel.lerp(Vector2(float(p["breeze_x"]), float(p["fall_y"])), clampf(delta * 3.2, 0.0, 1.0))
			var flutter: float = sin(age * float(p["freq"]) + float(p["phase"])) * float(p["amp"])
			var wpos: Vector2 = (p["pos"] as Vector2) + (vel + Vector2(flutter, absf(flutter) * 0.14)) * delta
			p["vel"] = vel
			p["pos"] = wpos
		i -= 1
	queue_redraw()


func _is_outfit_active(body: CharacterBody2D, app: AppearanceComponent) -> bool:
	if not body.visible or app == null:
		return false
	if int(body.get("swim")) != 0 or float(body.get("_sink")) > 6.0:
		return false
	return String(app.parse_outfit_id().get("style", "")) == OUTFIT_STYLE


func _spawn_petal(body: CharacterBody2D, app: AppearanceComponent, gentle_idle: bool) -> void:
	if _petals.size() >= MAX_PETALS:
		return
	var offset: Vector2 = Vector2(
		_rng.randf_range(-5.5, 5.5),
		_rng.randf_range(-19.0, -9.0) if gentle_idle else _rng.randf_range(-17.0, -8.0)
	)
	var trail_vel: Vector2 = -body.velocity * 0.16
	var breeze_x: float = _rng.randf_range(4.0, 11.5) * (-1.0 if _rng.randf() < 0.35 else 1.0)
	var init_vel: Vector2 = trail_vel + Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-4.0, 5.0))
	var roll: float = _rng.randf()
	var kind: int = 0 ## 0 = pearl silk, 1 = blush lotus, 2 = misty ice-blue peony, 3 = champagne-gold fleck
	if roll < 0.44:
		kind = 1
	elif roll < 0.80:
		kind = 0
	elif roll < 0.95:
		kind = 2
	else:
		kind = 3
	var tint: Color = app.arm_tint() if app != null else Color.WHITE
	_petals.append({
		"pos": body.global_position + offset,
		"vel": init_vel,
		"breeze_x": breeze_x,
		"fall_y": _rng.randf_range(6.5, 11.5),
		"age": 0.0,
		"life": _rng.randf_range(1.25, 1.85) if gentle_idle else _rng.randf_range(0.95, 1.48),
		"phase": _rng.randf_range(0.0, TAU),
		"freq": _rng.randf_range(4.2, 6.8),
		"amp": _rng.randf_range(7.0, 13.5),
		"spin": _rng.randf_range(4.5, 8.2),
		"kind": kind,
		"tint": tint,
	})


func _spawn_step_burst(body: CharacterBody2D, app: AppearanceComponent) -> void:
	var tint: Color = app.arm_tint() if app != null else Color.WHITE
	for k: int in 7:
		if _petals.size() >= MAX_PETALS:
			break
		var ang: float = (TAU * float(k) / 7.0) + _rng.randf_range(-0.25, 0.25)
		var dir: Vector2 = Vector2.from_angle(ang)
		var kind: int = 2 if k % 3 == 0 else (1 if k % 2 == 0 else 0)
		_petals.append({
			"pos": body.global_position + Vector2(dir.x * 5.0, -15.0 + dir.y * 5.0),
			"vel": dir * _rng.randf_range(18.0, 32.0) + Vector2(0.0, -8.0),
			"breeze_x": _rng.randf_range(-8.0, 10.0),
			"fall_y": _rng.randf_range(7.0, 12.0),
			"age": 0.0,
			"life": _rng.randf_range(0.95, 1.45),
			"phase": _rng.randf_range(0.0, TAU),
			"freq": _rng.randf_range(5.0, 7.5),
			"amp": _rng.randf_range(8.0, 14.0),
			"spin": _rng.randf_range(6.0, 9.5),
			"kind": kind,
			"tint": tint,
		})
	queue_redraw()


func _draw() -> void:
	if _petals.is_empty():
		return
	var amb: Color = TimeManager.ambient_color()
	var grade_soft: Color = amb.lerp(Color.WHITE, 0.50)
	var grade_lume: Color = amb.lerp(Color.WHITE, 0.80)
	var origin: Vector2 = global_position

	for p: Dictionary in _petals:
		var age: float = float(p["age"])
		var life: float = float(p["life"])
		var u: float = clampf(age / maxf(life, 0.01), 0.0, 1.0)
		var fade_in: float = clampf(age / 0.12, 0.0, 1.0)
		var fade_out: float = clampf((1.0 - u) / 0.34, 0.0, 1.0)
		var alpha: float = fade_in * fade_out * 0.92
		if alpha <= 0.02:
			continue

		var kind: int = int(p["kind"])
		var base_hi: Color = COL_PEARL
		var base_lo: Color = COL_PEARL_SHADE
		var grade: Color = grade_soft
		if kind == 0:
			var tint: Color = p["tint"] as Color
			if absf(tint.r - 1.0) + absf(tint.g - 1.0) + absf(tint.b - 1.0) > 0.02:
				base_hi = tint.lerp(COL_PEARL, 0.52)
				base_lo = tint.darkened(0.18).lerp(COL_PEARL_SHADE, 0.42)
		elif kind == 1:
			base_hi = COL_BLUSH
			base_lo = COL_BLUSH_SHADE
		elif kind == 2:
			base_hi = COL_ICE
			base_lo = COL_ICE_SHADE
			grade = grade_lume
		else:
			base_hi = COL_GOLD
			base_lo = COL_GOLD.darkened(0.22)
			grade = grade_lume

		var col_hi: Color = Color(base_hi.r * grade.r, base_hi.g * grade.g, base_hi.b * grade.b, alpha)
		var col_lo: Color = Color(base_lo.r * grade.r, base_lo.g * grade.g, base_lo.b * grade.b, alpha * 0.88)
		var at: Vector2 = ((p["pos"] as Vector2) - origin).round()

		if kind == 3:
			draw_rect(Rect2(at, Vector2(1.0, 1.0)), col_hi)
			continue

		var turn: int = posmod(floori(age * float(p["spin"]) + float(p["phase"])), 4)
		match turn:
			0:
				draw_rect(Rect2(at, Vector2(1.0, 1.0)), col_hi)
				draw_rect(Rect2(at + Vector2(1.0, 0.0), Vector2(1.0, 1.0)), col_lo)
			1:
				draw_rect(Rect2(at, Vector2(1.0, 1.0)), col_hi)
				draw_rect(Rect2(at + Vector2(1.0, 1.0), Vector2(1.0, 1.0)), col_lo)
			2:
				draw_rect(Rect2(at, Vector2(1.0, 1.0)), col_lo)
				draw_rect(Rect2(at + Vector2(0.0, 1.0), Vector2(1.0, 1.0)), col_hi)
			_:
				draw_rect(Rect2(at + Vector2(1.0, 0.0), Vector2(1.0, 1.0)), col_hi)
				draw_rect(Rect2(at + Vector2(0.0, 1.0), Vector2(1.0, 1.0)), col_lo)
