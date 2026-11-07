class_name BossBar
extends Control
## The health bar of a boss, top centre of the HUD. It is the big sibling of `VoidHealthBar`: the same crack of violet light
## (here two pixels thick, longer, wilder), but unmistakably a boss: the name stands over it in gold at double size with
## magenta eyes watching on both sides, thorned diamonds close the crack, a dotted rail with ticks runs beside it, and two
## black fractures at one third and two thirds mark the phases. It tears open from the middle when a fight starts, jolts and
## flares when a phase falls, and shatters into shards when the boss dies.
## Use `get_tree().call_group("boss_bar", "track", "NAME", health_component)`; `release()` lets it fade without a death.
## Cosmetic and local: every peer draws it from the replicated health of the boss.

const W: int = 300 ## length of the whole crack in px
const SIZE: Vector2 = Vector2(380, 52)
const CRACK_Y: int = 34
const SMEAR: Color = Color("040109")
const RAIL: Color = Color("4a2f9a")
const GHOST: Color = Color("c0307f")
const VEIN_LOW: Color = Color("e0407f")
const BUD: Color = Color("e04aa8")
const FLASH: Color = Color("efe6ff")
const GOLD: Color = Color("ffd98a")
const PHASES: Array[float] = [1.0 / 3.0, 2.0 / 3.0]
const INTRO_TIME: float = 1.1
const DEATH_TIME: float = 1.3
const GHOST_DELAY: float = 0.5
const GHOST_SPEED: float = 0.5
const LOW: float = 0.25
const SHARD_GRAVITY: float = 120.0

enum State { HIDDEN, OPEN, DYING }

var _state: State = State.HIDDEN
var _health: HealthComponent
var _title: String = ""
var _time: float = 0.0
var _grow: float = 0.0 ## 0..1 the crack tearing open from the middle
var _dying: float = 0.0
var _ghost: float = 1.0
var _ghost_wait: float = 0.0
var _flash: float = 0.0
var _impact: float = 0.0 ## a phase fell: jolt and flare
var _last_phase: int = 0
var _shards: Array[Dictionary] = []
var _seed: int = 0
var _glow: Control
var _fade: float = 1.0 ## 1 -> 0 while it withers
var _cover: float = 1.0 ## the HUD dims it behind full-screen windows
var _covered: bool = false
var _title_node: VoidTitle ## the name in the black gooey face (docs/void_face.md)


func _ready() -> void:
	add_to_group("boss_bar")
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE)
	offset_top = 10.0
	offset_bottom = 10.0 + SIZE.y
	material = Unlit.material()
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.size = SIZE
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	modulate.a = 0.0
	visible = false
	set_process(false)


## Shows the bar for `health`; it tears open. Calling it again switches to another boss.
func track(title: String, health: HealthComponent) -> void:
	_untrack()
	_health = health
	_title = title
	if _title_node == null:
		_title_node = VoidTitle.new()
		add_child(_title_node)
	_title_node.setup(title, "tiny", float(hash(title) % 7))
	_title_node.set_ink(1.0)
	_title_node.visible = false
	_seed = int(hash(title) % 997)
	_state = State.OPEN
	_grow = 0.0
	_dying = 0.0
	_time = 0.0
	_ghost = _fraction()
	_last_phase = _phase()
	_shards.clear()
	_flash = 0.4
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	visible = true
	_fade = 1.0
	modulate.a = 1.0
	set_process(true)


## The boss is gone without dying (left the fight, despawned): the bar withers.
func release() -> void:
	if _state == State.OPEN:
		_untrack()
		_state = State.DYING
		_dying = 0.0


## The HUD hides the bar while the map, inventory or a menu covers the screen.
func set_covered(covered: bool) -> void:
	_covered = covered


func _untrack() -> void:
	if _health != null and is_instance_valid(_health):
		if _health.damaged.is_connected(_on_damaged):
			_health.damaged.disconnect(_on_damaged)
		if _health.died.is_connected(_on_died):
			_health.died.disconnect(_on_died)
	_health = null


## The name condenses out of the smoke when the crack has torn open, stutters when a phase falls and crumbles upwards when the boss dies.
## It stays small and well clear of the crack (its goo is held short so no drop reaches it).
func _sync_title() -> void:
	if _title_node == null:
		return
	_title_node.visible = _grow > 0.45 and _state != State.HIDDEN
	var born: float = clampf((_grow - 0.45) / 0.4, 0.0, 1.0)
	var dissolve: float = clampf(_dying * 1.1, 0.0, 1.0) if _state == State.DYING else 0.0
	_title_node.set_look(born * 1.4, dissolve, clampf(_impact * 1.6, 0.0, 1.0), 0.45, 0.08)
	_title_node.place(Vector2(roundf(SIZE.x * 0.5 - float(_title_node.ink_size.x) * 0.5), 3.0) + _shake())


func _fraction() -> float:
	if _health == null or not is_instance_valid(_health):
		return 0.0
	return clampf(_health.current / maxf(_health.max_health, 0.001), 0.0, 1.0)


func _phase() -> int: ## 0 full .. 2 last third
	var f: float = _fraction()
	return 2 if f <= PHASES[0] else (1 if f <= PHASES[1] else 0)


func _fill() -> int:
	return ceili(W * _fraction())


func _x0() -> int:
	return int((SIZE.x - W) * 0.5)


func _on_damaged(amount: float, _from: Vector2, _knockback: float) -> void:
	if _state != State.OPEN:
		return
	_flash = 0.14
	_ghost_wait = GHOST_DELAY
	var count: int = clampi(int(amount / maxf(_health.max_health, 1.0) * 60.0) + 4, 4, 18)
	_spawn_shards(Vector2(_x0() + _fill(), CRACK_Y), count, 1.0)


func _on_died() -> void:
	if _state != State.OPEN:
		return
	_untrack()
	_state = State.DYING
	_dying = 0.0
	_flash = 0.35
	_spawn_shards(Vector2(SIZE.x * 0.5, CRACK_Y), 0, 1.0)
	for i: int in range(0, W, 3): ## the whole crack shatters
		_spawn_shards(Vector2(_x0() + i, _row_unsafe(i)), 1, 1.6)


func _spawn_shards(at: Vector2, count: int, speed: float) -> void:
	for i: int in count:
		_shards.append({
			"pos": at + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)),
			"vel": Vector2(randf_range(-30.0, 40.0), randf_range(-55.0, -8.0)) * speed,
			"life": randf_range(0.5, 1.0) * speed,
			"max": 1.0,
			"color": VoidGlow.VEIN_LIGHT if randf() < 0.65 else GHOST,
			"wide": randf() < 0.4,
		})


var _rys: PackedInt32Array = PackedInt32Array()
var _rys_frame: int = -1
var _spark_frame: int = -1
var _spark_fill: int = -1
var _spark_val: int = -1


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta, 0.0)
	_impact = maxf(_impact - delta, 0.0)
	match _state:
		State.OPEN:
			if _health == null or not is_instance_valid(_health):
				release()
			else:
				_grow = minf(_grow + delta / INTRO_TIME, 1.0)
				var phase: int = _phase()
				if phase > _last_phase:
					_impact = 0.55
					_flash = 0.3
					_spawn_shards(Vector2(_x0() + _fill(), CRACK_Y), 24, 1.4)
				_last_phase = phase
				if _ghost_wait > 0.0:
					_ghost_wait -= delta
				elif _ghost > _fraction():
					_ghost = maxf(_fraction(), _ghost - GHOST_SPEED * delta)
				elif _fraction() > _ghost:
					_ghost = _fraction()
		State.DYING:
			_dying += delta
			_fade = clampf(1.0 - (_dying - 0.5) / (DEATH_TIME - 0.5), 0.0, 1.0)
			if _dying >= DEATH_TIME:
				_state = State.HIDDEN
				visible = false
				set_process(false)
	for s: Dictionary in _shards:
		s["life"] = float(s["life"]) - delta
		var vel: Vector2 = s["vel"] as Vector2
		vel.y += SHARD_GRAVITY * delta
		s["vel"] = vel
		s["pos"] = (s["pos"] as Vector2) + vel * delta
	_cover = move_toward(_cover, 0.0 if _covered else 1.0, delta * 8.0)
	modulate.a = _fade * _cover
	_sync_title()
	_shards = _shards.filter(func(s: Dictionary) -> bool: return float(s["life"]) > 0.0)
	if modulate.a > 0.0 and visible:
		if _rys.size() != W + 1:
			_rys.resize(W + 1)
		for i: int in W + 1:
			_rys[i] = _ry_calc(i)
		_rys_frame = Engine.get_process_frames()
	queue_redraw()
	_glow.queue_redraw()


# --- shape of the crack -----------------------------------------------------------------------------------

func _rate() -> float:
	return lerpf(1.8, 0.8, smoothstep(0.0, LOW * 1.5, _fraction()))


func _low() -> float:
	return 1.0 - smoothstep(0.0, LOW, _fraction())


func _row_unsafe(i: int) -> int:
	return _ry(i)


## Height of the crack at column `i`: wilder than the small bars (up to 3 px), always twitching and rippling.
func _ry(i: int) -> int:
	if i >= 0 and i < _rys.size() and _rys_frame == Engine.get_process_frames():
		return _rys[i] ## drawn many times per column and frame: computed once in `_process`
	return _ry_calc(i)


func _ry_calc(i: int) -> int:
	if i < 0:
		return CRACK_Y
	var base: int = int(hash(Vector2i(i / 4, _seed)) % 5) - 2
	var tick: int = floori(_time * (13.0 + 9.0 * _low()))
	if int(hash(Vector2i(i / 2 + 31, tick + _seed)) % 4) == 0:
		base += 1 if int(hash(Vector2i(i, tick)) % 2) == 0 else -1
	base += roundi(sin(float(i) * 0.35 - _time * 5.0 + float(_seed)) * 0.9)
	var taper: float = clampf(float(i) / 5.0, 0.0, 1.0)
	return CRACK_Y + clampi(roundi(base * taper), -3, 3)


func _visible_column(i: int) -> bool: ## the tear opens from the middle outwards
	var reach: float = W * 0.5 * smoothstep(0.0, 1.0, _grow)
	return absf(float(i) - W * 0.5) <= reach


func _gap(i: int) -> bool:
	var low: float = _low()
	if low <= 0.0:
		return false
	return float(hash(Vector2i(i, floori(_time * 10.0) + _seed + 7)) % 100) / 100.0 < low * 0.3


## 0 at both ends of the track, 1 from seven px inside: the crack thins out like a real bolt instead of being capped.
func _end(i: int) -> float:
	return clampf(float(mini(i, W - 1 - i)) / 7.0, 0.0, 1.0)


func _spark(fill: int) -> int:
	var frame: int = Engine.get_process_frames()
	if frame != _spark_frame or fill != _spark_fill:
		_spark_frame = frame
		_spark_fill = fill
		_spark_val = _spark_calc(fill)
	return _spark_val


func _spark_calc(fill: int) -> int:
	var period: float = 1.4
	var k: int = floori(_time / period)
	if int(hash(Vector2i(k, _seed + 3)) % 2) != 0:
		return -1
	var phase: float = fposmod(_time, period) / 0.4
	return -1 if phase >= 1.0 else int(phase * float(fill))


func _flicker(i: int) -> bool:
	return int(hash(Vector2i(i, floori(_time * 16.0) + _seed + 19)) % 30) == 0


func _twig(i: int) -> int:
	if i < 6 or int(hash(Vector2i(i, _seed + 11)) % 6) != 0:
		return 0
	return -1 if int(hash(Vector2i(i, _seed + 13)) % 2) == 0 else 1


func _shake() -> Vector2:
	if _impact <= 0.0:
		return Vector2.ZERO
	var k: int = floori(_time * 40.0)
	return Vector2(float(int(hash(k) % 5)) - 2.0, float(int(hash(k + 91) % 3)) - 1.0) * (_impact / 0.55)


func _title_pos(width_px: int) -> Vector2:
	var glitch: float = float(int(hash(floori(_time * 20.0)) % 3) - 1) if _impact > 0.0 else 0.0
	return Vector2(roundf(SIZE.x * 0.5 - width_px * 0.5 + glitch), 3.0)


# --- drawing ------------------------------------------------------------------------------------------------

func _draw() -> void:
	if modulate.a <= 0.0:
		return
	draw_set_transform(_shake(), 0.0, Vector2.ONE)
	var x0: int = _x0()
	var y: int = CRACK_Y
	var fill: int = _fill() if _state == State.OPEN else 0
	var ghost_to: int = ceili(W * _ghost) if _state == State.OPEN else 0
	var low: float = _low()
	var main: Color = VoidGlow.VEIN.lightened(0.15).lerp(VEIN_LOW, low)
	var light: Color = VoidGlow.VEIN_LIGHT.lerp(BUD, low * 0.7)
	var edge: int = maxi(fill, ghost_to)
	# The black the crack is torn into.
	for i: int in range(W):
		if not _visible_column(i):
			continue
		var r: int = _ry(i)
		if i < edge or _state == State.DYING:
			draw_rect(Rect2(x0 + i, r - 4, 1, 10), Color(SMEAR, 0.55 * _end(i)))
		if i >= edge and i % 2 == 0 and _state == State.OPEN:
			draw_rect(Rect2(x0 + i, r, 1, 1), Color(RAIL, 0.5 * _end(i))) ## what could still be
	# What was just lost, dying as glitch pixels.
	for i: int in range(fill, ghost_to):
		if _visible_column(i) and int(hash(Vector2i(i, floori(_time * 14.0) + _seed)) % 3) != 0:
			draw_rect(Rect2(x0 + i, _ry(i), 1, 2), Color(GHOST, 0.85))
	# The crack, two pixels thick.
	if _state == State.OPEN:
		for i: int in range(fill):
			if not _visible_column(i) or _gap(i):
				continue
			var r: int = _ry(i)
			var prev: int = _ry(i - 1)
			var top: int = mini(r, prev)
			var ef: float = _end(i)
			var span: int = absi(r - prev) + (2 if ef >= 0.5 else 1)
			var fade: float = 0.3 + 0.7 * ef
			var wave: float = VoidGlow.pulse(_time, -float(i) * 0.012, _rate(), 0.55)
			draw_rect(Rect2(x0 + i, maxi(r, prev) + span, 1, 1), Color(SMEAR, 0.95 * ef))
			draw_rect(Rect2(x0 + i, top, 1, span), Color(main.lightened((wave - 0.55) * 0.4), fade))
			draw_rect(Rect2(x0 + i, top, 1, 1), Color(light.lightened((wave - 0.55) * 0.4), fade))
			var tw: int = _twig(i)
			if tw != 0 and i < fill - 2:
				draw_rect(Rect2(x0 + i, r + tw * 2, 1, 1), main)
				draw_rect(Rect2(x0 + i + 1, r + tw * 3, 1, 1), Color(main, 0.85))
				draw_rect(Rect2(x0 + i + 2, r + tw * 4, 1, 1), Color(main, 0.55))
		for i: int in range(fill):
			if not _visible_column(i):
				continue
			var d: int = absi(i - _spark(fill)) if _spark(fill) >= 0 else 99
			if d <= 4:
				draw_rect(Rect2(x0 + i, _ry(i), 1, 2), Color(FLASH, 1.0 - float(d) * 0.2))
			elif _flicker(i):
				draw_rect(Rect2(x0 + i, _ry(i), 1, 2), Color(FLASH, 0.9))
		if _flash > 0.0:
			for i: int in range(fill):
				if _visible_column(i):
					draw_rect(Rect2(x0 + i, _ry(i), 1, 2), Color(FLASH, 0.85 * minf(_flash / 0.14, 1.0)))
	# The two phase marks are part of the crack: it forks into a star of thin veins there (dim and dead when the crack has gone past).
	if _grow > 0.6:
		for p: float in PHASES:
			var col: int = roundi(W * p)
			var passed: bool = _fraction() <= p
			var base: Color = (VEIN_LOW if passed else main) if _state == State.OPEN else RAIL
			var beat_p: float = 0.55 + 0.45 * VoidGlow.beat(_time, p, 0.8)
			var cy: int = _ry(col)
			var live: float = 0.35 if (passed or _state != State.OPEN) else 1.0
			var arm: int = 0
			for dx: int in [-1, 1]:
				for dy: int in [-1, 1]:
					var length: int = 3 + int(hash(Vector2i(arm, _seed + col)) % 4)
					var yy: int = cy
					for k: int in range(1, length + 1):
						if k % 2 == 0 and int(hash(Vector2i(k + arm * 7, _seed + col + 5)) % 3) == 0:
							yy += dy ## kinks like a real bolt: now and then a step straight on
						else:
							yy += dy if k > 1 else 0
						var fade: float = (1.0 - float(k - 1) / float(length + 1)) * live
						draw_rect(Rect2(x0 + col + dx * k, yy, 1, 1), Color(base, fade))
					arm += 1
			draw_rect(Rect2(x0 + col - 1, cy, 3, 1), Color(base.lightened(0.3), live))
			draw_rect(Rect2(x0 + col, cy, 1, 1), Color(FLASH, beat_p * live))
	# Shards.
	for s: Dictionary in _shards:
		var p: Vector2 = (s["pos"] as Vector2).round()
		var fade: float = clampf(float(s["life"]) * 2.0, 0.0, 1.0)
		draw_rect(Rect2(p, Vector2(2 if bool(s["wide"]) else 1, 1)), Color(s["color"] as Color, fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_glow() -> void:
	if modulate.a <= 0.0:
		return
	_glow.draw_set_transform(_shake(), 0.0, Vector2.ONE)
	var x0: int = _x0()
	var beat: float = VoidGlow.pulse(_time, 0.0, _rate(), 0.4)
	var low: float = _low()
	if _state == State.OPEN:
		var fill: int = _fill()
		for i: int in range(fill):
			if _visible_column(i):
				_glow.draw_rect(Rect2(x0 + i, _ry(i) - 2, 1, 6), Color(VoidGlow.VEIN, 0.18 * VoidGlow.pulse(_time, -float(i) * 0.012, _rate(), 0.4)))
		if fill > 0:
			VoidGlow.halo(_glow, Vector2(x0 + fill + 1, _ry(fill - 1) + 1), BUD, beat * (1.5 + 0.6 * low), 0.95)
			var spark: int = _spark(fill)
			if spark >= 0 and _visible_column(spark):
				VoidGlow.halo(_glow, Vector2(x0 + spark, _ry(spark) + 1), FLASH, 1.0, 0.9)
		for i: int in range(6, maxi(fill - 2, 0)):
			if not _visible_column(i):
				continue
			if _flicker(i):
				VoidGlow.halo(_glow, Vector2(x0 + i, _ry(i)), VoidGlow.VEIN_LIGHT, 0.9, 0.45)
			var tw: int = _twig(i)
			if tw != 0:
				VoidGlow.halo(_glow, Vector2(x0 + i + 1, _ry(i) + tw * 3), VoidGlow.VEIN, VoidGlow.beat(_time, -float(i) * 0.012, _rate()) * 1.2, 0.45)
	if _grow > 0.6 and _state == State.OPEN:
		for p: float in PHASES:
			var col: int = roundi(W * p)
			var passed: bool = _fraction() <= p
			VoidGlow.halo(_glow, Vector2(x0 + col, _ry(col)), VEIN_LOW if passed else VoidGlow.VEIN_LIGHT, (0.5 if passed else 0.9) + 0.5 * VoidGlow.beat(_time, p, 0.8), 0.7)
	_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
