class_name QuartzHealthBar
extends Node2D
## Frameless crystalline sun-quartz & sandstone health vein for arcane desert constructs.
## Visible only while damaged and alive; sheds glittering quartz & amber splinters when struck.

const SEAM: Color = Color("2b191d")
const REMAINDER: Color = Color("9e6844")
const GHOST: Color = Color("ffb347")
const QUARTZ_DARK: Color = Color("3cc0c6")
const QUARTZ_MID: Color = Color("78f4e6")
const QUARTZ_CORE: Color = Color("d0fff8")
const GOLD_GLINT: Color = Color("ffe488")
const LOW_TINT: Color = Color("ff8a5c")
const FLASH: Color = Color("ffffff")
const GHOST_DELAY: float = 0.34
const GHOST_SPEED: float = 1.15
const FLASH_TIME: float = 0.14
const FADE_SPEED: float = 6.0
const SHARD_LIFE: float = 0.58
const SHARD_GRAVITY: float = 115.0

@export var health: HealthComponent
@export var auto_width: bool = true
@export var width: int = 24

var _time: float = 0.0
var _ghost: float = 1.0
var _ghost_wait: float = 0.0
var _flash: float = 0.0
var _seed: int = 0
var _shards: Array[Dictionary] = []
var _glow: Node2D


func _ready() -> void:
	if health == null:
		health = get_node("../HealthComponent") as HealthComponent
	_seed = int(get_instance_id() % 997)
	material = Unlit.material()
	_ghost = _fraction()
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow = Node2D.new()
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	health.changed.connect(func(_c: float, _m: float) -> void: _refresh())
	health.damaged.connect(_on_damaged)
	modulate.a = 0.0
	_refresh()


func _w() -> int:
	if not auto_width:
		return width
	return clampi(roundi(16.0 + sqrt(maxf(health.max_health, 1.0)) * 1.45), 20, 44)


func _fraction() -> float:
	return clampf(health.current / maxf(health.max_health, 0.001), 0.0, 1.0)


func _shown() -> bool:
	return health.current > 0.0 and health.current < health.max_health


func _fill() -> int:
	return ceili(float(_w()) * _fraction())


func _refresh() -> void:
	if _fraction() > _ghost:
		_ghost = _fraction()
	set_process(true)


func _on_damaged(amount: float, _from: Vector2, _knockback: float) -> void:
	_flash = FLASH_TIME
	_ghost_wait = GHOST_DELAY
	var count: int = clampi(int(amount / maxf(health.max_health, 1.0) * 38.0) + 3, 3, 12)
	var tip: Vector2 = Vector2(float(-_w() / 2 + _fill()), 0.0)
	for i: int in count:
		var warm: bool = randf() < 0.38
		_shards.append({
			"pos": tip + Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0)),
			"vel": Vector2(randf_range(-20.0, 26.0), randf_range(-34.0, -7.0)),
			"life": SHARD_LIFE * randf_range(0.6, 1.0),
			"color": GOLD_GLINT if warm else QUARTZ_CORE,
			"wide": randf() < 0.35,
		})
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	var want: float = 1.0 if _shown() else 0.0
	modulate.a = move_toward(modulate.a, want, FADE_SPEED * delta)
	_flash = maxf(_flash - delta, 0.0)
	if _ghost_wait > 0.0:
		_ghost_wait -= delta
	elif _ghost > _fraction():
		_ghost = maxf(_fraction(), _ghost - GHOST_SPEED * delta)
	for s: Dictionary in _shards:
		s["life"] = float(s["life"]) - delta
		var vel: Vector2 = s["vel"] as Vector2
		vel.y += SHARD_GRAVITY * delta
		s["vel"] = vel
		s["pos"] = (s["pos"] as Vector2) + vel * delta
	_shards = _shards.filter(func(s: Dictionary) -> bool: return float(s["life"]) > 0.0)
	queue_redraw()
	_glow.queue_redraw()
	if want == 0.0 and modulate.a <= 0.0 and _shards.is_empty():
		set_process(false)


func _facet_y(col: int) -> int:
	var h: int = (col * 37 + _seed) % 7
	if h == 0:
		return -1
	if h == 3:
		return 1
	return 0


func _draw() -> void:
	var w: int = _w()
	var left: int = -w / 2
	var fill: int = _fill()
	var ghost_px: int = ceili(float(w) * _ghost)
	var low_mix: float = 1.0 - smoothstep(0.0, 0.32, _fraction())
	var flash_mix: float = clampf(_flash / FLASH_TIME, 0.0, 1.0)
	for i: int in w:
		var x: int = left + i
		var y: int = _facet_y(i)
		draw_rect(Rect2(Vector2(x - 1, y - 1), Vector2(3, 4)), Color(SEAM, 0.85))
		if i < fill:
			var shimmer: float = 0.5 + 0.5 * sin(_time * 5.2 + float(i) * 0.45)
			var base: Color = QUARTZ_DARK.lerp(QUARTZ_MID, shimmer).lerp(LOW_TINT, low_mix * 0.55)
			var top: Color = QUARTZ_CORE.lerp(GOLD_GLINT, 0.35 * (1.0 - shimmer)).lerp(FLASH, flash_mix)
			draw_rect(Rect2(Vector2(x, y), Vector2(1, 2)), base.lerp(FLASH, flash_mix * 0.65))
			if i % 3 != 2:
				draw_rect(Rect2(Vector2(x, y), Vector2(1, 1)), top)
		elif i < ghost_px:
			draw_rect(Rect2(Vector2(x, y), Vector2(1, 2)), GHOST)
		elif i % 2 == 0:
			draw_rect(Rect2(Vector2(x, y + 1), Vector2(1, 1)), Color(REMAINDER, 0.55))
	if fill > 0:
		var tip_x: int = left + fill - 1
		var tip_y: int = _facet_y(fill - 1)
		draw_rect(Rect2(Vector2(tip_x, tip_y - 1), Vector2(2, 3)), GOLD_GLINT.lerp(FLASH, flash_mix))
	for s: Dictionary in _shards:
		var a: float = clampf(float(s["life"]) / SHARD_LIFE, 0.0, 1.0)
		var pos: Vector2 = (s["pos"] as Vector2).round()
		var sz: Vector2 = Vector2(2, 1) if bool(s["wide"]) else Vector2.ONE
		draw_rect(Rect2(pos - Vector2.ONE, sz + Vector2(2, 2)), Color(SEAM, a * 0.6))
		draw_rect(Rect2(pos, sz), Color(s["color"] as Color, a))


func _draw_glow() -> void:
	var w: int = _w()
	var left: int = -w / 2
	var fill: int = _fill()
	if fill <= 0:
		return
	var pulse: float = 0.14 + 0.05 * sin(_time * 4.4)
	_glow.draw_rect(Rect2(Vector2(left - 2, -2), Vector2(fill + 4, 6)), Color(QUARTZ_MID, pulse))
	var tip_x: int = left + fill - 1
	_glow.draw_rect(Rect2(Vector2(tip_x - 2, -3), Vector2(5, 7)), Color(GOLD_GLINT, 0.22))
