class_name BossBar
extends Control
## The health bar of a boss, top centre of the HUD. It is the big sibling of `VoidHealthBar`: the same crack of violet light
## (here two pixels thick, longer, wilder), but unmistakably a boss: the name stands over it in gold in the game's pixel font (like the judgement's URTEIL), thorned diamonds close the crack, a dotted rail with ticks runs beside it, and two
## black fractures at one third and two thirds mark the phases. It tears open from the middle when a fight starts, jolts and
## flares when a phase falls, and shatters into shards when the boss dies.
## Use `get_tree().call_group("boss_bar", "track", "NAME", health_component)`; `release()` lets it fade without a death.
## Cosmetic and local: every peer draws it from the replicated health of the boss.

const W: int = 300 ## length of the whole crack in px
const SIZE: Vector2 = Vector2(400, 72)
const CRACK_Y: int = 34
const STAGGER_Y: int = 50 ## golden stagger bar underneath the HP crack (docs/dungeon_konzept.md 3.3)
const STAGGER_H: int = 6
const TITLE_Y: int = 8 ## the name's top row (the pixel font at double size is 14 rows high, the crack lies below)
const TITLE_SCALE: int = 2 ## the name is the pixel font at this scale (whole pixels)
const TITLE_TRACK: int = 1 ## extra pixels (before scaling) between the letters
const SMEAR: Color = Color("040109")
const RAIL: Color = Color("4a2f9a")
const GHOST: Color = Color("c0307f")
const VEIN_LOW: Color = Color("e0407f")
const BUD: Color = Color("e04aa8")
const FLASH: Color = Color("efe6ff")
const GOLD: Color = Color("ffd98a")
const STAGGER_DEEP: Color = Color("8c6322")
const STAGGER_GOLD: Color = Color("ffd98a")
const STAGGER_CORE: Color = Color("fff7d6")
## Lost-Ark multi-layer HP bar palette (index 0 = final x1 bar, cycling upwards for x2..xN).
const BAR_LAYERS: Array[Dictionary] = [
	{"main": Color("e0407f"), "light": Color("ff92c8")}, ## x1 final urgent magenta-red
	{"main": Color("d9a338"), "light": Color("fff0b0")}, ## x2 warm amber-gold
	{"main": Color("32b57e"), "light": Color("9af2c8")}, ## x3 emerald
	{"main": Color("36b8c4"), "light": Color("8cf7f0")}, ## x4 Steinsetzer turquoise
	{"main": Color("8a4dff"), "light": Color("d4b8ff")}, ## x5+ signature Void violet
]
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
var _stagger: StaggerComponent
var _bars: int = 1 ## Lost-Ark layered HP count (1 = classic single bar, >=2 = x5/x10/x15 multi-layer)
var _last_bar: int = 1
var _stagger_open: float = 0.0 ## 0..1 smooth reveal of golden stagger bar below HP crack
var _stagger_flash: float = 0.0
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
var _dirty: bool = true
var _idle_time: float = 0.0
var _motion: bool = false ## a smooth change (ghost, cover) that needs no more than MOTION_REDRAW_INTERVAL
var _reach: float = 0.0 ## per redraw: half width of the opened tear (`_visible_column`)
var _low_now: float = 0.0 ## per redraw: `_low()`, asked for every column by `_gap`
const IDLE_REDRAW_INTERVAL: float = 0.1 ## idle shimmer at 10 FPS: whole-pixel twitching reads better a little jerky (docs/hud_v2_konzept.md 8.4)
const MOTION_REDRAW_INTERVAL: float = 0.033 ## the ghost draining and the cover fading need at most 30 FPS


## For the HUD director: the bar is on screen only while it tracks a boss.
func hud_busy() -> bool:
	return is_fighting()

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
## `bars`: Lost-Ark multi-layer HP count (1 = classic single bar, e.g. 5 for Vorgath, 10 for Mornath).
## `stagger`: optional `StaggerComponent` displayed live as a golden bar underneath the HP crack.
func track(title: String, health: HealthComponent, bars: int = 1, stagger: StaggerComponent = null) -> void:
	_untrack()
	_health = health
	_stagger = stagger
	if _stagger == null and health != null and health.get_parent() != null:
		_stagger = health.get_parent().get_node_or_null("StaggerComponent") as StaggerComponent
	_bars = maxi(bars, 1)
	_title = title
	_seed = int(hash(title) % 997)
	_state = State.OPEN
	_grow = 0.0
	_dying = 0.0
	_time = 0.0
	_ghost = _layer_fraction()
	_last_phase = _phase()
	_last_bar = _current_bar()
	_stagger_open = 1.0 if (_stagger != null and _stagger.active) else 0.0
	_stagger_flash = 0.0
	_shards.clear()
	_flash = 0.4
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.changed.connect(_on_health_changed)
	if _stagger != null and is_instance_valid(_stagger):
		_stagger.stagger_changed.connect(_on_stagger_changed)
		_stagger.stagger_broken.connect(_on_stagger_broken)
	_dirty = true
	visible = true
	_fade = 1.0
	modulate.a = 1.0
	set_process(true)


## Returns the active bar number (1.._bars) in multi-layer mode, or 1 in classic mode.
func current_bar_number() -> int:
	return _current_bar()


func _current_bar() -> int:
	if _bars <= 1:
		return 1
	var f: float = _fraction()
	if f <= 0.0:
		return 0
	return clampi(ceili(f * float(_bars)), 1, _bars)


## 0..1 fill within the currently active HP layer (equals `_fraction()` when `_bars == 1`).
func _layer_fraction() -> float:
	var f: float = _fraction()
	if _bars <= 1:
		return f
	if f <= 0.0:
		return 0.0
	var scaled: float = f * float(_bars)
	var b: int = clampi(ceili(scaled), 1, _bars)
	return clampf(scaled - float(b - 1), 0.0, 1.0)


func _layer_colors(bar_num: int) -> Dictionary:
	var idx: int = clampi(bar_num - 1, 0, 999) % BAR_LAYERS.size()
	return BAR_LAYERS[idx] as Dictionary


func _on_stagger_changed(_cur: float, _maximum: float, _left: float, _dur: float) -> void:
	_dirty = true


func _on_stagger_broken(_source_peer: int) -> void:
	_stagger_flash = 0.5
	_impact = maxf(_impact, 0.45)
	for i: int in range(0, W, 12):
		_shards.append({
			"pos": Vector2(_x0() + i, STAGGER_Y + 3),
			"vel": Vector2(randf_range(-40.0, 40.0), randf_range(-65.0, -15.0)),
			"life": randf_range(0.45, 0.85),
			"max": 0.85,
			"color": STAGGER_GOLD if (i % 24 == 0) else STAGGER_CORE,
			"wide": true,
		})
	_dirty = true


## The boss is gone without dying (left the fight, despawned): the bar withers.
func release() -> void:
	if _state == State.OPEN:
		_untrack()
		_state = State.DYING
		_dying = 0.0


## The HUD hides the bar while the map, inventory or a menu covers the screen.
func set_covered(covered: bool) -> void:
	_covered = covered


## True while a boss fight is actively open (turns false on death or release).
func is_fighting() -> bool:
	return _state == State.OPEN


func _untrack() -> void:
	if _health != null and is_instance_valid(_health):
		if _health.damaged.is_connected(_on_damaged):
			_health.damaged.disconnect(_on_damaged)
		if _health.died.is_connected(_on_died):
			_health.died.disconnect(_on_died)
		if _health.changed.is_connected(_on_health_changed):
			_health.changed.disconnect(_on_health_changed)
	if _stagger != null and is_instance_valid(_stagger):
		if _stagger.stagger_changed.is_connected(_on_stagger_changed):
			_stagger.stagger_changed.disconnect(_on_stagger_changed)
		if _stagger.stagger_broken.is_connected(_on_stagger_broken):
			_stagger.stagger_broken.disconnect(_on_stagger_broken)
	_health = null
	_stagger = null


func _fraction() -> float:
	if _health == null or not is_instance_valid(_health):
		return 0.0
	return clampf(_health.current / maxf(_health.max_health, 0.001), 0.0, 1.0)


func _phase() -> int: ## 0 full .. 2 last third
	var f: float = _fraction()
	return 2 if f <= PHASES[0] else (1 if f <= PHASES[1] else 0)


func _fill() -> int:
	return ceili(W * _layer_fraction())


func _x0() -> int:
	return int((SIZE.x - W) * 0.5)


func _on_health_changed(_c: float, _m: float) -> void:
	_dirty = true


func _on_damaged(amount: float, _from: Vector2, _knockback: float) -> void:
	if _state != State.OPEN:
		return
	_dirty = true
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
	_stagger_flash = maxf(_stagger_flash - delta, 0.0)
	match _state:
		State.OPEN:
			if _health == null or not is_instance_valid(_health):
				release()
			else:
				_grow = minf(_grow + delta / INTRO_TIME, 1.0)
				var bar_now: int = _current_bar()
				if _bars > 1 and bar_now < _last_bar:
					_impact = 0.42
					_flash = 0.25
					_ghost = 1.0
					_ghost_wait = 0.15
					_spawn_shards(Vector2(_x0() + _fill(), CRACK_Y), 18, 1.35)
					_dirty = true
				_last_bar = bar_now
				var phase: int = _phase()
				if phase > _last_phase:
					_impact = 0.55
					_flash = 0.3
					_spawn_shards(Vector2(_x0() + _fill(), CRACK_Y), 24, 1.4)
					_dirty = true
				_last_phase = phase
				var lf: float = _layer_fraction()
				if _ghost_wait > 0.0:
					_ghost_wait -= delta ## the ghost holds still while it waits: nothing to redraw
				elif _ghost > lf:
					_ghost = maxf(lf, _ghost - GHOST_SPEED * delta)
					_motion = true
				elif lf > _ghost:
					_ghost = lf
					_dirty = true
				var want_stagger: float = 1.0 if (_stagger != null and is_instance_valid(_stagger) and _stagger.active) else 0.0
				var prev_stagger: float = _stagger_open
				_stagger_open = move_toward(_stagger_open, want_stagger, delta * 5.5)
				if absf(_stagger_open - prev_stagger) > 0.001 or want_stagger > 0.5:
					_motion = true
		State.DYING:
			_dying += delta
			_fade = clampf(1.0 - (_dying - 0.5) / (DEATH_TIME - 0.5), 0.0, 1.0)
			_dirty = true
			if _dying >= DEATH_TIME:
				_state = State.HIDDEN
				visible = false
				set_process(false)
				return
	for s: Dictionary in _shards:
		s["life"] = float(s["life"]) - delta
		var vel: Vector2 = s["vel"] as Vector2
		vel.y += SHARD_GRAVITY * delta
		s["vel"] = vel
		s["pos"] = (s["pos"] as Vector2) + vel * delta
	var prev_cover: float = _cover
	_cover = move_toward(_cover, 0.0 if _covered else 1.0, delta * 8.0)
	if absf(_cover - prev_cover) > 0.001:
		_motion = true
	modulate.a = _fade * _cover
	_shards = _shards.filter(func(s: Dictionary) -> bool: return float(s["life"]) > 0.0)
	if not _shards.is_empty():
		_dirty = true

	if not visible or modulate.a <= 0.0:
		return

	var is_active_anim: bool = (_state == State.DYING or _grow < 1.0 or _flash > 0.0 or _impact > 0.0 or not _shards.is_empty())
	_idle_time += delta
	if is_active_anim or _dirty or _idle_time >= IDLE_REDRAW_INTERVAL or (_motion and _idle_time >= MOTION_REDRAW_INTERVAL):
		_idle_time = 0.0
		_dirty = false
		_motion = false
		_reach = W * 0.5 * smoothstep(0.0, 1.0, _grow)
		_low_now = _low()
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
	return absf(float(i) - W * 0.5) <= _reach


func _gap(i: int) -> bool:
	var low: float = _low_now
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
	return Vector2(roundf(SIZE.x * 0.5 - width_px * 0.5 + glitch), float(TITLE_Y))


## The name in the game's own pixel font, gold like the judgement's word URTEIL: it fades in when the crack has torn open, flashes when a phase falls
## (white-violet, with a jolt) and fades out when the boss dies.
func _draw_title() -> void:
	if _title == "" or _grow <= 0.45:
		return
	var born: float = clampf((_grow - 0.45) / 0.4, 0.0, 1.0)
	var gone: float = clampf(_dying * 1.1, 0.0, 1.0) if _state == State.DYING else 0.0
	var alpha: float = born * (1.0 - gone)
	if alpha <= 0.0:
		return
	var tone: Color = GOLD.lerp(FLASH, clampf(_impact * 1.6, 0.0, 1.0))
	var step: int = PixelText.ADVANCE + TITLE_TRACK
	var width: int = maxi(_title.length() * step - TITLE_TRACK - 1, 0)
	var at: Vector2 = _title_pos(width * TITLE_SCALE)
	draw_set_transform(_shake(), 0.0, Vector2(TITLE_SCALE, TITLE_SCALE))
	for i: int in _title.length(): ## letter by letter, so the spacing can be wider than the font's own
		PixelText.draw(self, _title[i], Vector2i(int(at.x) / TITLE_SCALE + i * step, int(at.y) / TITLE_SCALE), Color(tone, alpha), Color(SMEAR, alpha))
	draw_set_transform(_shake(), 0.0, Vector2.ONE)


# --- drawing ------------------------------------------------------------------------------------------------

func _draw() -> void:
	if modulate.a <= 0.0:
		return
	draw_set_transform(_shake(), 0.0, Vector2.ONE)
	_draw_title()
	var x0: int = _x0()
	var y: int = CRACK_Y
	var fill: int = _fill() if _state == State.OPEN else 0
	var ghost_to: int = ceili(W * _ghost) if _state == State.OPEN else 0
	var low: float = _low()
	var bar_now: int = _current_bar()
	var main: Color = VoidGlow.VEIN.lightened(0.15).lerp(VEIN_LOW, low)
	var light: Color = VoidGlow.VEIN_LIGHT.lerp(BUD, low * 0.7)
	var under_main: Color = Color(RAIL, 0.5)
	if _bars > 1 and bar_now > 0:
		var pal: Dictionary = _layer_colors(bar_now)
		main = pal["main"] as Color
		light = pal["light"] as Color
		if bar_now > 1:
			var upal: Dictionary = _layer_colors(bar_now - 1)
			under_main = (upal["main"] as Color).darkened(0.28)
	var edge: int = maxi(fill, ghost_to)
	# The black the crack is torn into.
	for i: int in range(W):
		if not _visible_column(i):
			continue
		var r: int = _ry(i)
		if i < edge or _state == State.DYING or (_bars > 1 and bar_now > 1):
			draw_rect(Rect2(x0 + i, r - 4, 1, 10), Color(SMEAR, 0.55 * _end(i)))
		if i >= edge and _state == State.OPEN:
			if _bars > 1 and bar_now > 1:
				draw_rect(Rect2(x0 + i, r, 1, 2), Color(under_main, 0.82 * _end(i))) ## gleaming next HP bar beneath!
			elif i % 2 == 0:
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
		var spark_at: int = _spark(fill)
		for i: int in range(fill):
			if not _visible_column(i):
				continue
			var d: int = absi(i - spark_at) if spark_at >= 0 else 99
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
	# Lost-Ark multi-layer HP counter ("x5") to the right of the crack.
	if _bars > 1 and _state == State.OPEN and _grow > 0.5 and bar_now > 0:
		var tag: String = "x%d" % bar_now
		var tag_col: Color = GOLD.lerp(FLASH, clampf(_impact * 1.4, 0.0, 1.0))
		draw_set_transform(_shake(), 0.0, Vector2(2.0, 2.0))
		PixelText.draw(self, tag, Vector2i((x0 + W + 6) / 2, (CRACK_Y - 6) / 2), tag_col, SMEAR)
		draw_set_transform(_shake(), 0.0, Vector2.ONE)
	# Integrated Golden Stagger Bar underneath the HP crack (docs/dungeon_konzept.md 3.3).
	if _stagger_open > 0.01 and _state == State.OPEN:
		var sw: int = roundi(float(W - 40) * smoothstep(0.0, 1.0, _stagger_open))
		var sx: int = int(SIZE.x * 0.5 - float(sw) * 0.5)
		var sy: int = STAGGER_Y
		var sf: float = _stagger.fraction() if (_stagger != null and is_instance_valid(_stagger)) else 0.0
		var tf: float = _stagger.time_fraction() if (_stagger != null and is_instance_valid(_stagger)) else 0.0
		draw_rect(Rect2(sx - 2, sy - 2, sw + 4, STAGGER_H + 4), Color(SMEAR, 0.88 * _stagger_open))
		draw_rect(Rect2(sx - 1, sy - 1, sw + 2, STAGGER_H + 2), Color(STAGGER_DEEP, 0.85 * _stagger_open))
		draw_rect(Rect2(sx, sy, sw, STAGGER_H), Color(Color("1a1026"), 0.92 * _stagger_open))
		var sfill: int = roundi(float(sw) * sf)
		if sfill > 0:
			var scol: Color = STAGGER_GOLD.lerp(STAGGER_CORE, clampf(_stagger_flash * 2.0, 0.0, 1.0))
			draw_rect(Rect2(sx, sy, sfill, STAGGER_H), Color(scol, _stagger_open))
			draw_rect(Rect2(sx, sy, sfill, 2), Color(STAGGER_CORE, 0.85 * _stagger_open))
		## Thin turquoise countdown rail along the bottom edge of the stagger bar
		var tfill: int = roundi(float(sw) * tf)
		if tfill > 0:
			draw_rect(Rect2(sx, sy + STAGGER_H + 1, tfill, 1), Color(Color("4df2e0"), 0.9 * _stagger_open))
		if _stagger_open > 0.6:
			PixelText.draw(self, "TAUMEL", Vector2i(sx - 34, sy - 1), Color(STAGGER_GOLD, _stagger_open), SMEAR)
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
