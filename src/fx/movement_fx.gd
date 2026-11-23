class_name MovementFx
extends Node2D
## Crisp pixel-art micro-VFX for Shadowspore 2.0 Movement (`V6`, `V7`, `V8`, `V12`):
## - Lore signature ("Ellie = Shadowspore"): 2-3 tiny dark-violet/lavender spore flecks on hard
##   sprint-pivots, ledge landings, and shadow-step push-offs (zero smoke!), plus a 1-2 px warm
##   golden Sun-Quartz glint at her throat choker (`TalismanArt` collar anchor) on condensation!
## - Biome Footfalls 2.0: morning-dew droplets (05:30-09:00), meadow petals, sinking witch-green
##   spores in Hexenwald, and singing sun-quartz sparks on `quartz`.
## - True terrain-anchored ground shadow ellipse while Ellie is airborne (`Vault` / `Ledge Hop`).

const SPORE_COLORS: Array[Color] = [
	Color("34185e"), Color("6636ad"), Color("9468ee"), Color("cbaaff"),
]
const DEW_COLORS: Array[Color] = [
	Color("78f4e6"), Color("d0fff8"), Color("bfe9ff"),
]
const PETAL_COLORS: Array[Color] = [
	Color("faf5e8"), Color("d0ebff"), Color("e4d4fa"),
]
const WITCH_COLORS: Array[Color] = [
	Color("66c44a"), Color("a8ff6a"), Color("d8ffbe"),
]
const QUARTZ_COLORS: Array[Color] = [
	Color("e5e3f8"), Color("fff0b0"), Color("e6c468"),
]

class PixelFlecks:
	var world_pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 2.0
	var z_vel: float = 14.0
	var grav: float = 55.0
	var age: float = 0.0
	var life: float = 0.32
	var col: Color = Color.WHITE
	var size: Vector2 = Vector2(1.0, 1.0)
	var unlit: bool = false


class _UnlitOverlay extends Node2D:
	var owner_fx: MovementFx

	func _ready() -> void:
		z_index = 3
		material = Unlit.material()

	func _draw() -> void:
		if owner_fx != null:
			owner_fx._draw_unlit(self)


var _player: Player
var _unlit: _UnlitOverlay
var _flecks: Array[PixelFlecks] = []
var _choker_glint: float = 0.0 ## > 0 while Valdric's Sun-Quartz choker flashes (`0.18 s`)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	z_index = -1
	_rng.randomize()
	_player = get_parent() as Player
	_unlit = _UnlitOverlay.new()
	_unlit.name = "MovementUnlit"
	_unlit.owner_fx = self
	add_child(_unlit)


func trigger_choker_glint(duration: float = 0.20) -> void:
	_choker_glint = maxf(_choker_glint, duration)
	if _unlit != null:
		_unlit.queue_redraw()


## Spawns 2-3 subtle dark-violet/silver spore flecks (`V6`) — never smoke!
func spawn_spore_flecks(world_pos: Vector2, dir: Vector2, count: int = 3) -> void:
	var back: Vector2 = -dir.normalized() if dir.length_squared() > 0.01 else Vector2.UP
	for i: int in count:
		if _flecks.size() >= 36:
			break
		var f: PixelFlecks = PixelFlecks.new()
		var spread_a: float = _rng.randf_range(-0.65, 0.65)
		f.world_pos = world_pos + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-2.0, 1.0))
		f.vel = back.rotated(spread_a) * _rng.randf_range(16.0, 34.0)
		f.z_h = _rng.randf_range(2.0, 7.0)
		f.z_vel = _rng.randf_range(10.0, 22.0)
		f.grav = 42.0
		f.life = _rng.randf_range(0.22, 0.34)
		f.col = SPORE_COLORS[i % SPORE_COLORS.size()]
		f.size = Vector2(2.0, 1.0) if i == 0 else Vector2(1.0, 1.0)
		f.unlit = (i == count - 1) ## Tiny lavender-core spark stays legible at night
		_flecks.append(f)


## Biome-specific footfall poetry (`V7`): morning dew, meadow petals, witch spores, and quartz sparks.
func on_biome_footstep(world_pos: Vector2, surface_id: String, velocity: Vector2, gait: int) -> void:
	var spd: float = velocity.length()
	if spd < 38.0 or _flecks.size() >= 32:
		return
	var back: Vector2 = -velocity.normalized()

	# 1. Singing Sun-Quartz sparks on `quartz` when jogging/sprinting
	if surface_id == "quartz" and gait >= 1:
		var n_q: int = 2 if gait == 2 else 1
		for _i: int in n_q:
			_add_fleck(world_pos, back, QUARTZ_COLORS[_rng.randi() % QUARTZ_COLORS.size()], 24.0, 22.0, 68.0, 0.28, true)
		return

	# 2. Hexenwald witch-green sinking spores on bare/hex ground
	if BiomeBlend.amount_at(world_pos) > 0.45:
		if _rng.randf() < (0.75 if gait >= 2 else 0.4):
			_add_fleck(world_pos, back * 0.5, WITCH_COLORS[_rng.randi() % WITCH_COLORS.size()], 10.0, 12.0, 18.0, 0.55, true)
		return

	# 3. Morning dew droplets (05:30 = 0.23 .. 09:15 = 0.385) & floral petals on lush grass
	if surface_id == "grass":
		var tod: float = TimeManager.time_of_day
		var morning_dew: bool = tod >= 0.22 and tod <= 0.39
		if morning_dew and (gait >= 1 or _rng.randf() < 0.45):
			_add_fleck(world_pos, back, DEW_COLORS[_rng.randi() % DEW_COLORS.size()], 22.0, 20.0, 74.0, 0.30, false)
		if gait >= 2 and _rng.randf() < 0.38:
			_add_fleck(world_pos, back, PETAL_COLORS[_rng.randi() % PETAL_COLORS.size()], 18.0, 16.0, 24.0, 0.52, false)


func _add_fleck(pos: Vector2, back: Vector2, col: Color, h_spd: float, z_v: float, grav: float, life: float, unlit: bool) -> void:
	var f: PixelFlecks = PixelFlecks.new()
	f.world_pos = pos + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-1.0, 1.0))
	f.vel = back.rotated(_rng.randf_range(-0.55, 0.55)) * _rng.randf_range(h_spd * 0.6, h_spd * 1.2)
	f.z_h = _rng.randf_range(1.0, 3.0)
	f.z_vel = z_v * _rng.randf_range(0.8, 1.2)
	f.grav = grav
	f.life = life
	f.col = col
	f.unlit = unlit
	_flecks.append(f)


func _process(delta: float) -> void:
	var dirty: bool = false
	if _choker_glint > 0.0:
		_choker_glint = maxf(_choker_glint - delta, 0.0)
		dirty = true

	if not _flecks.is_empty():
		dirty = true
		var i: int = _flecks.size() - 1
		while i >= 0:
			var f: PixelFlecks = _flecks[i]
			f.age += delta
			if f.age >= f.life:
				_flecks.remove_at(i)
			else:
				f.world_pos += f.vel * delta
				f.vel = f.vel.move_toward(Vector2.ZERO, 48.0 * delta)
				f.z_vel -= f.grav * delta
				f.z_h = maxf(0.0, f.z_h + f.z_vel * delta)
			i -= 1

	if _player != null and _player.air_height > 0.2:
		dirty = true

	if dirty:
		queue_redraw()
		if _unlit != null:
			_unlit.queue_redraw()


func _draw() -> void:
	# 1. Airborne terrain-pinned ground shadow ellipse (`V8`, `V12`)
	if _player != null and _player.air_height > 0.2:
		var shrink: float = clampf(1.0 - _player.air_height / 24.0, 0.62, 1.0)
		var rx: float = roundf(8.5 * shrink)
		var ry: float = maxf(1.0, roundf(2.4 * shrink))
		var alpha: float = 0.27 * shrink
		var col: Color = Color(0.02, 0.01, 0.04, alpha)
		for py: int in range(-int(ry), int(ry) + 1):
			var span_x: float = rx * sqrt(maxf(0.0, 1.0 - pow(float(py) / maxf(ry, 0.5), 2.0)))
			draw_rect(Rect2(roundf(-span_x), float(py), roundf(span_x * 2.0), 1.0), col)

	# 2. World-lit flecks
	for f: PixelFlecks in _flecks:
		if f.unlit:
			continue
		var a: float = clampf(1.0 - maxf(0.0, (f.age / f.life - 0.5) / 0.5), 0.0, 1.0)
		var c: Color = f.col
		c.a = a
		var local_p: Vector2 = to_local(f.world_pos)
		draw_rect(Rect2(roundf(local_p.x), roundf(local_p.y - f.z_h), f.size.x, f.size.y), c)


func _draw_unlit(canvas: CanvasItem) -> void:
	# 1. Unlit spore / witch / sun-quartz flecks
	for f: PixelFlecks in _flecks:
		if not f.unlit:
			continue
		var a: float = clampf(1.0 - maxf(0.0, (f.age / f.life - 0.45) / 0.55), 0.0, 1.0)
		var c: Color = f.col
		c.a = a
		var local_p: Vector2 = canvas.to_local(f.world_pos)
		canvas.draw_rect(Rect2(roundf(local_p.x), roundf(local_p.y - f.z_h), f.size.x, f.size.y), c)

	# 2. V6: 1-2 px warm golden Sun-Quartz glint right at Ellie's collar anchor!
	if _choker_glint > 0.0 and _player != null and _player._sprite != null and _player._sprite.visible:
		var jdata: PackedInt32Array = TalismanArt.frame_data(_player._sprite.texture, _player._sprite.frame)
		var collar_pos: Vector2 = Vector2(0.0, -32.0)
		var visible_front: bool = true
		if jdata.size() >= 16:
			if jdata[10] < TalismanArt.TORSO_HIDDEN:
				visible_front = false
			else:
				collar_pos = Vector2(floorf(float(jdata[4]) / 10.0), floorf(float(jdata[5]) / 10.0) - 1.0)
		if visible_front:
			var k: float = clampf(_choker_glint / 0.20, 0.0, 1.0)
			var base_p: Vector2 = (_player._sprite.position + collar_pos).round()
			canvas.draw_rect(Rect2(base_p, Vector2(1.0, 1.0)), Color(1.0, 0.96, 0.72, k))
			if k > 0.45:
				canvas.draw_rect(Rect2(base_p + Vector2(-1.0, 0.0), Vector2(3.0, 1.0)), Color(0.90, 0.76, 0.40, (k - 0.45) * 0.85))
				canvas.draw_rect(Rect2(base_p + Vector2(0.0, -1.0), Vector2(1.0, 3.0)), Color(0.90, 0.76, 0.40, (k - 0.45) * 0.85))
