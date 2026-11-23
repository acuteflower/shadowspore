class_name WebbedFx
extends Node2D
## Tactile dark-violet Void-mycelium silk strands binding a player's ankles while `"webbed"` is active.
## When snapped (via ShadowStep, sword swing, or expiry), spawns a crisp 0.22s pixel silk-snap burst.

const SILK_OUTLINE: Color = Color("040208")
const SILK_DARK: Color = Color("1a1030")
const SILK_VEIN: Color = Color("8a4dff")
const SILK_DEW: Color = Color("ecd2ff")


class SnapBurst:
	extends Node2D
	var _age: float = 0.0
	var _shards: Array[Vector4] = []

	func _ready() -> void:
		z_index = 2
		material = Unlit.material()
		for i: int in 8:
			var ang: float = float(i) * (TAU / 8.0) + 0.25
			var spd: float = 28.0 + float(i % 3) * 11.0
			_shards.append(Vector4(cos(ang) * spd, sin(ang) * spd * 0.65 - 15.0, cos(ang) * 4.0, -3.0 + sin(ang) * 2.0))

	func _process(delta: float) -> void:
		_age += delta
		if _age >= 0.22:
			queue_free()
			return
		for i: int in _shards.size():
			var s: Vector4 = _shards[i]
			s.z += s.x * delta
			s.w += s.y * delta
			s.y += 68.0 * delta
			_shards[i] = s
		queue_redraw()

	func _draw() -> void:
		var a: float = clampf(1.0 - _age / 0.22, 0.0, 1.0)
		for i: int in _shards.size():
			var s: Vector4 = _shards[i]
			var p: Vector2 = Vector2(roundf(s.z), roundf(s.w))
			draw_rect(Rect2(p, Vector2(2.0 if i % 2 == 0 else 1.0, 1.0)), Color(SILK_DEW if i % 3 == 0 else SILK_VEIN, a))


var _effects: StatusEffects
var _time: float = 0.0


func _ready() -> void:
	z_index = 2
	material = Unlit.material()


func bind(effects: StatusEffects) -> void:
	_effects = effects


func end() -> void:
	if not is_inside_tree() or get_tree().current_scene == null:
		return
	var burst: SnapBurst = SnapBurst.new()
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse: float = 0.65 + 0.35 * sin(_time * 11.0)
	for band: int in 3:
		var y_base: float = -2.0 - float(band) * 2.2
		var sway: float = sin(_time * 9.0 + float(band) * 1.7) * 0.8
		for dx: int in range(-6, 7):
			var sag: float = cos(float(dx) / 6.5 * PI * 0.5) * 1.4
			var py: float = roundf(y_base + sag * (1.0 if band != 1 else -0.8) + sway * 0.4)
			var px: float = float(dx)
			draw_rect(Rect2(Vector2(px, py + 1.0), Vector2.ONE), Color(SILK_OUTLINE, 0.72))
			var is_dew: bool = (absi(dx + band * 2) % 5 == 0)
			var col: Color = SILK_DEW if is_dew else (SILK_VEIN if absi(dx) % 2 == 0 else SILK_DARK)
			draw_rect(Rect2(Vector2(px, py), Vector2.ONE), Color(col, 0.88 * pulse if is_dew else 0.84))
