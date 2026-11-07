class_name VoidHealthBar
extends Node2D
## Health of the shadow creatures, drawn as a tear in the world: a jagged crack of violet light whose length is the
## remaining health. It twitches in whole pixels like the creatures themselves, sprouts thin side veins, carries the
## shared heartbeat (`VoidGlow`) and ends in a magenta bud. What is lost flickers away as dying magenta glitch pixels
## and shards of void break off at every hit; the weaker the creature, the more the crack stutters and breaks up.
## No frame, no box. Visible only while damaged and alive. Cosmetic: every peer draws it from the replicated health.

const SMEAR: Color = Color("040109") ## the black the crack is torn into, so it reads on any ground
const REMAINDER: Color = Color("4a2f9a") ## faint dots where the crack could still run
const GHOST: Color = Color("c0307f")
const VEIN_LOW: Color = Color("e0407f")
const BUD: Color = Color("e04aa8")
const FLASH: Color = Color("efe6ff")
const GHOST_DELAY: float = 0.35
const GHOST_SPEED: float = 1.1 ## health fractions per second
const FLASH_TIME: float = 0.14
const FADE_SPEED: float = 6.0
const LOW: float = 0.3
const SHARD_LIFE: float = 0.6
const SHARD_GRAVITY: float = 110.0

@export var health: HealthComponent
@export var auto_width: bool = true ## width follows the creature's maximum health (EnemyScaling changes it after spawn)
@export var width: int = 22 ## used when auto_width is off

var _time: float = 0.0
var _ghost: float = 1.0
var _ghost_wait: float = 0.0
var _flash: float = 0.0
var _seed: int = 0
var _shards: Array[Dictionary] = [] ## {pos, vel, life, color, wide}
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


func _fraction() -> float:
	return clampf(health.current / maxf(health.max_health, 0.001), 0.0, 1.0)


func _shown() -> bool:
	return health.current > 0.0 and health.current < health.max_health


func _fill() -> int:
	return ceili(_w() * _fraction())


func _refresh() -> void:
	if _fraction() > _ghost:
		_ghost = _fraction()
	set_process(true)


func _on_damaged(amount: float, _from: Vector2, _knockback: float) -> void:
	_flash = FLASH_TIME
	_ghost_wait = GHOST_DELAY
	var count: int = clampi(int(amount / maxf(health.max_health, 1.0) * 40.0) + 3, 3, 12)
	var tip: Vector2 = Vector2(-_w() / 2 + _fill(), 0)
	for i: int in count:
		var violet: bool = randf() < 0.7
		_shards.append({
			"pos": tip + Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0)),
			"vel": Vector2(randf_range(-18.0, 26.0), randf_range(-34.0, -6.0)),
			"life": SHARD_LIFE * randf_range(0.6, 1.0),
			"color": VoidGlow.VEIN_LIGHT if violet else GHOST,
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


func _rate() -> float:
	return lerpf(1.8, 0.8, smoothstep(0.0, LOW * 1.5, _fraction()))


func _low() -> float:
	return 1.0 - smoothstep(0.0, LOW, _fraction())


## Height of the crack at column `i`: a fixed ragged shape, now and then twitched a pixel by the void.
func _row(i: int) -> int:
	if i < 0:
		return 0
	var base: int = int(hash(Vector2i(i / 3, _seed)) % 3) - 1
	var tick: int = floori(_time * (13.0 + 9.0 * _low()))
	if int(hash(Vector2i(i / 2 + 31, tick + _seed)) % 5) == 0:
		base += 1 if int(hash(Vector2i(i, tick)) % 2) == 0 else -1
	base += roundi(sin(float(i) * 0.5 - _time * 6.0 + float(_seed)) * 0.75) ## a wave runs through the crack
	var taper: float = clampf(float(i) / 3.0, 0.0, 1.0) ## the root starts straight
	return clampi(roundi(base * taper), -2, 2)


## Columns where the crack breaks up when weak.
func _gap(i: int) -> bool:
	var low: float = _low()
	if low <= 0.0:
		return false
	var tick: int = floori(_time * 10.0)
	return float(hash(Vector2i(i, tick + _seed + 7)) % 100) / 100.0 < low * 0.35


## Column of a spark racing from the root to the tip (-1 when none): every 1.1 s there is a one in three chance.
func _spark(fill: int) -> int:
	var period: float = 1.1
	var k: int = floori(_time / period)
	if int(hash(Vector2i(k, _seed + 3)) % 3) != 0:
		return -1
	var phase: float = fposmod(_time, period) / 0.32
	return -1 if phase >= 1.0 else int(phase * float(fill))


## A pixel that lights up white for one tick.
func _flicker(i: int) -> bool:
	return int(hash(Vector2i(i, floori(_time * 16.0) + _seed + 19)) % 38) == 0


## A little diamond closing an end of the crack; `dir` points away from the crack.
func _cap(px: int, py: int, dir: int, edge: Color, core: Color, strength: float) -> void:
	draw_rect(Rect2(px, py - 2, 1, 5), Color(SMEAR, 0.5 * strength))
	draw_rect(Rect2(px, py - 1, 1, 1), Color(edge, strength))
	draw_rect(Rect2(px, py + 1, 1, 1), Color(edge, strength))
	draw_rect(Rect2(px, py, 1, 1), Color(core, strength))
	draw_rect(Rect2(px + dir, py, 1, 1), Color(edge, 0.6 * strength))


func _twig(i: int) -> int: ## 0 none, -1 grows up, 1 down
	if i < 4 or int(hash(Vector2i(i, _seed + 11)) % 7) != 0:
		return 0
	return -1 if int(hash(Vector2i(i, _seed + 13)) % 2) == 0 else 1


func _draw() -> void:
	if modulate.a <= 0.0:
		return
	var x: int = -_w() / 2
	var fill: int = _fill()
	var ghost_to: int = ceili(_w() * _ghost)
	var low: float = _low()
	var main: Color = VoidGlow.VEIN.lightened(0.12).lerp(VEIN_LOW, low)
	var light: Color = VoidGlow.VEIN_LIGHT.lerp(BUD, low * 0.7)
	# The black the crack is torn into.
	for i: int in range(0, maxi(fill, ghost_to)):
		var y: int = _row(i)
		draw_rect(Rect2(x + i, y - 2, 1, 5), Color(SMEAR, 0.5))
	# What could still be: faint dots along the empty stretch.
	for i: int in range(maxi(fill, ghost_to), _w()):
		if i % 2 == 0:
			draw_rect(Rect2(x + i, _row(i), 1, 1), Color(REMAINDER, 0.5))
	# What was just lost: magenta glitch pixels, dying.
	for i: int in range(fill, ghost_to):
		if int(hash(Vector2i(i, floori(_time * 14.0) + _seed)) % 3) != 0:
			draw_rect(Rect2(x + i, _row(i), 1, 1), Color(GHOST, 0.8))
	# The crack itself.
	for i: int in range(fill):
		if _gap(i):
			continue
		var y: int = _row(i)
		var prev: int = _row(i - 1)
		var top: int = mini(y, prev)
		var span: int = absi(y - prev) + 1
		var wave: float = VoidGlow.pulse(_time, -float(i) * 0.012, _rate(), 0.55)
		draw_rect(Rect2(x + i, maxi(y, prev) + 1, 1, 1), Color(SMEAR, 0.95)) ## shadow under the line
		draw_rect(Rect2(x + i, top, 1, span), main.lightened((wave - 0.55) * 0.35))
		draw_rect(Rect2(x + i, top, 1, 1), light.lightened((wave - 0.55) * 0.4))
		var tw: int = _twig(i)
		if tw != 0 and i < fill - 1:
			draw_rect(Rect2(x + i, y + tw, 1, 1), main)
			draw_rect(Rect2(x + i + 1, y + tw * 2, 1, 1), Color(main, 0.85))
			draw_rect(Rect2(x + i + 2, y + tw * 3, 1, 1), Color(main, 0.55))
	# Closed ends: a small diamond node at the root, at the tip and (dim) where the crack could end.
	if fill > 0:
		_cap(x - 1, _row(0), -1, main, light, 1.0)
		_cap(x + fill, _row(fill - 1), 1, main, BUD, 1.0)
	if fill < _w() - 1:
		_cap(x + _w(), _row(_w() - 1), 1, REMAINDER, REMAINDER, 0.55)
	# Flashes: a spark racing along the crack and single pixels that flare for a tick.
	var spark: int = _spark(fill)
	for i: int in range(fill):
		var d: int = absi(i - spark) if spark >= 0 else 99
		if d <= 3:
			draw_rect(Rect2(x + i, _row(i), 1, 1), Color(FLASH, 1.0 - float(d) * 0.28))
		elif _flicker(i):
			draw_rect(Rect2(x + i, _row(i), 1, 1), Color(FLASH, 0.9))
	# The hit: the whole crack blinks white.
	if _flash > 0.0:
		var a: float = 0.85 * _flash / FLASH_TIME
		for i: int in range(fill):
			draw_rect(Rect2(x + i, _row(i), 1, 1), Color(FLASH, a))
	# Shards breaking off.
	for s: Dictionary in _shards:
		var p: Vector2 = (s["pos"] as Vector2).round()
		var fade: float = clampf(float(s["life"]) / (SHARD_LIFE * 0.5), 0.0, 1.0)
		draw_rect(Rect2(p, Vector2(2 if bool(s["wide"]) else 1, 1)), Color(s["color"] as Color, fade))


func _draw_glow() -> void:
	if modulate.a <= 0.0 or not _shown():
		return
	var x: int = -_w() / 2
	var fill: int = _fill()
	if fill <= 0:
		return
	var low: float = _low()
	var beat: float = VoidGlow.pulse(_time, 0.0, _rate(), 0.4)
	var tip: int = fill - 1
	for i: int in range(fill): # a soft light along the whole crack, strongest on the beat
		_glow.draw_rect(Rect2(x + i, _row(i) - 1, 1, 4), Color(VoidGlow.VEIN, 0.17 * VoidGlow.pulse(_time, -float(i) * 0.012, _rate(), 0.4)))
	VoidGlow.halo(_glow, Vector2(x + tip + 1, _row(tip)), BUD, beat * (1.4 + 0.6 * low), 0.95)
	VoidGlow.halo(_glow, Vector2(x - 1, _row(0)), VoidGlow.VEIN_LIGHT, beat * 0.9, 0.6)
	var spark: int = _spark(fill)
	if spark >= 0:
		VoidGlow.halo(_glow, Vector2(x + spark, _row(spark)), FLASH, 1.0, 0.9)
	for i: int in range(fill):
		if _flicker(i):
			VoidGlow.halo(_glow, Vector2(x + i, _row(i)), VoidGlow.VEIN_LIGHT, 0.8, 0.45)
	for i: int in range(4, fill - 1):
		var tw: int = _twig(i)
		if tw != 0:
			VoidGlow.halo(_glow, Vector2(x + i + 1, _row(i) + tw * 2), VoidGlow.VEIN, VoidGlow.beat(_time, -float(i) * 0.012, _rate()) * 1.2, 0.45)


## 6 + 4 * sqrt(max health): 38 HP = 31 px, 48 HP = 34 px, 80 HP = 42 px, 150 HP = 55 px.
func _w() -> int:
	if not auto_width:
		return width
	return clampi(roundi(6.0 + 4.0 * sqrt(health.max_health)), 20, 72)
