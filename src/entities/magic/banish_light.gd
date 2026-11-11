class_name BanishLight
extends SpellZone
## Bannlicht (docs/magie_konzept.md, school LICHT): a standing light round where Ellie stood when she struck the staff on the ground.
## The floor (magic_light_ground.gdshader) opens with a shock ring, a wall of light columns rises from its rim (magic_light_curtain.gdshader,
## the back half behind whoever stands inside, the front half in front), motes climb out of it. Shadow creatures inside burn (host: a tick of
## `dps * tick` every `tick` seconds, `take_tick`, credited to the caster) and sear visibly on every peer: white-teal flecks tear off them.
## Tier III (BANNKREIS): while it stands the night treats it as a lamp (TownManager.add_magic_light). Tier V (SONNENKERN): every `every`
## seconds a ring breaks out of the core and hits everything inside for `dps * burst`. Brennglas V (NACHBRAND): when it goes out it flares once
## for `dps * flare`.

const CORE: Color = Color("82f2dc")
const DEEP: Color = Color("1d8a86")
const WHITE: Color = Color("ecfff6")
const SEAR: Array[Color] = [Color("ecfff6"), Color("9ff5e4"), Color("5fd9c8")]
const WALL_HEIGHT: float = 30.0

var _ground: Node2D
var _back: Node2D
var _front: Node2D
var _light: NightLight
var _pulse_clock: float = 0.0
var _pulse: float = 0.0 ## 0..1 the SONNENKERN ring on its way out
var _flare: float = 0.0
var _flared: bool = false
var _burn_glow: float = 0.0 ## 0..1 something burns inside (drawn hotter)
var _sear_clock: float = 0.0
var _registered: bool = false
var _closing: bool = false
var _sizzle: float = 0.0


func _build() -> void:
	var reach: float = radius * 1.7 + 10.0
	var box: Rect2 = Rect2(-reach, -reach * SQUASH - 4.0, reach * 2.0, reach * SQUASH * 2.0 + 8.0)
	_ground = shader_quad("Floor", "res://assets/shaders/magic_light_ground.gdshader", box, -4)
	var wall_box: Rect2 = Rect2(-radius - 2.0, -radius * SQUASH - WALL_HEIGHT - 4.0, radius * 2.0 + 4.0, radius * SQUASH * 2.0 + WALL_HEIGHT + 8.0)
	_back = shader_quad("WallBack", "res://assets/shaders/magic_light_curtain.gdshader", wall_box, 0, Vector2(0.0, -roundf(radius * SQUASH)))
	_front = shader_quad("WallFront", "res://assets/shaders/magic_light_curtain.gdshader", wall_box, 0, Vector2(0.0, roundf(radius * SQUASH)))
	var look_seed: float = _rng.randf() * 100.0
	for node: Node2D in [_ground, _back, _front]:
		set_shader(node, "radius", radius)
		set_shader(node, "squash", SQUASH)
		set_shader(node, "seed", look_seed)
		set_shader(node, "core", CORE)
		set_shader(node, "deep", DEEP)
		set_shader(node, "white", WHITE)
	for node: Node2D in [_back, _front]:
		set_shader(node, "height", WALL_HEIGHT)
		set_shader(node, "offset", node.position)
	set_shader(_front, "front", 1.0)
	_light = NightLight.new()
	_light.radius = roundi(radius * 1.35)
	_light.squash = SQUASH
	_light.glow_color = Color("6ff0d8")
	_light.base_energy = 1.0
	_light.pulse = 0.1
	add_child(_light)
	if bool(params.get("perk3", false)):
		TownManager.add_magic_light(get_instance_id(), Vector3(global_position.x, global_position.y, radius))
		_registered = true
	SpellZone.sound(self, "light_open", global_position)
	for i: int in 26: ## the strike: a crown of motes thrown up out of the rim
		var a: float = _rng.randf() * TAU
		var at: Vector2 = Vector2(cos(a), sin(a) * SQUASH) * radius * _rng.randf_range(0.15, 0.5)
		mote(at, Vector2(cos(a), sin(a) * SQUASH) * _rng.randf_range(30.0, 80.0) + Vector2(0.0, -_rng.randf_range(10.0, 50.0)), _rng.randf_range(0.4, 0.9), SEAR[i % SEAR.size()], 2 if i % 4 == 0 else 1, 30.0, 3.0)


func _exit_tree() -> void:
	if _registered:
		TownManager.remove_magic_light(get_instance_id())


func _ending() -> float:
	return 0.9


func _update(delta: float) -> void:
	var t: float = clampf(_age / 0.3, 0.0, 1.0)
	var grow: float = 1.0 + 2.7 * pow(t - 1.0, 3.0) + 1.7 * pow(t - 1.0, 2.0) ## ease out with a small overshoot
	var fade: float = ending_amount()
	if fade > 0.0 and not _closing:
		_closing = true
		SpellZone.sound(self, "light_close", global_position, -4.0)
	if fade > 0.0 and _registered:
		TownManager.remove_magic_light(get_instance_id())
		_registered = false
	if fade > 0.0 and not _flared and float(params.get("flare", 0.0)) > 0.0:
		_flared = true
		_flare = 1.0
		SpellZone.sound(self, "light_pulse", global_position, 2.0)
		_host_flare()
		for i: int in 30:
			var a: float = TAU * i / 30.0
			mote(Vector2(cos(a), sin(a) * SQUASH) * radius, Vector2(cos(a), sin(a) * SQUASH) * 90.0 + Vector2(0.0, -30.0), 0.6, WHITE, 2 if i % 3 == 0 else 1, 0.0, 2.5)
	_flare = move_toward(_flare, 0.0, delta * 1.8)
	if float(params.get("every", 0.0)) > 0.0 and fade <= 0.0:
		_pulse_clock += delta
		if _pulse_clock >= float(params["every"]):
			_pulse_clock = 0.0
			_pulse = 0.001
			_host_pulse()
			SpellZone.sound(self, "light_pulse", global_position, -3.0)
	if _pulse > 0.0:
		_pulse += delta / 0.45
		if _pulse >= 1.0:
			_pulse = 0.0
	_sear(delta, fade)
	var burning: float = _burn_glow
	for node: Node2D in [_ground, _back, _front]:
		set_shader(node, "age", _age)
		set_shader(node, "grow", grow)
		set_shader(node, "fade", fade)
		set_shader(node, "burn", burning)
	set_shader(_ground, "pulse", _pulse)
	set_shader(_ground, "flare", _flare)
	if _light != null:
		_light.base_energy = (1.0 + 0.4 * _flare + 0.2 * burning) * (1.0 - fade)
	if fade <= 0.0 and _rng.randf() < delta * 14.0: ## motes rise off the wall all the time
		var a: float = _rng.randf() * TAU
		var on_rim: Vector2 = Vector2(cos(a), sin(a) * SQUASH) * radius * grow
		mote(on_rim + Vector2(0.0, -_rng.randf_range(0.0, WALL_HEIGHT * 0.6)), Vector2(_rng.randf_range(-4.0, 4.0), -_rng.randf_range(14.0, 30.0)), _rng.randf_range(0.8, 1.6), SEAR[_rng.randi() % SEAR.size()], 1, 0.0, 0.6)
	if fade > 0.0 and fade < 0.6 and _rng.randf() < delta * 40.0: ## going out: the wall breaks into motes
		var a2: float = _rng.randf() * TAU
		mote(Vector2(cos(a2), sin(a2) * SQUASH) * radius, Vector2(_rng.randf_range(-10.0, 10.0), -_rng.randf_range(20.0, 50.0)), 0.7, CORE, 1, 0.0, 1.0)


## Every peer: whatever stands burning in the light sheds flecks of white-teal light that are torn upwards.
func _sear(delta: float, fade: float) -> void:
	_sear_clock -= delta
	if _sear_clock > 0.0:
		_burn_glow = move_toward(_burn_glow, 0.0, delta * 1.5)
		return
	_sear_clock = 0.12
	if fade > 0.0:
		return
	var any: bool = false
	for box: HurtboxComponent in enemies_inside():
		any = true
		var body: Vector2 = box.global_position - global_position
		for k: int in 3:
			var at: Vector2 = body + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 4.0))
			mote(at, Vector2(_rng.randf_range(-12.0, 12.0), -_rng.randf_range(25.0, 55.0)), _rng.randf_range(0.3, 0.6), SEAR[k], 2 if k == 0 else 1, 20.0, 2.0)
	_burn_glow = 1.0 if any else move_toward(_burn_glow, 0.0, 0.2)
	_sizzle -= 0.12
	if any and _sizzle <= 0.0:
		_sizzle = 0.45
		SpellZone.sound(self, "light_sear", global_position, -6.0)


## Host: one tick of burning on every shadow creature inside.
func _host_tick(tick: float) -> void:
	var damage: float = float(params.get("dps", 0.0)) * tick
	if damage <= 0.0:
		return
	for box: HurtboxComponent in enemies_inside():
		box.health.take_tick(damage, caster)


## Host: SONNENKERN, the ring from the core hits everything inside.
func _host_pulse() -> void:
	if not multiplayer.is_server():
		return
	var damage: float = float(params.get("dps", 0.0)) * float(params.get("burst", 0.0))
	for box: HurtboxComponent in enemies_inside():
		box.take_hit(damage, global_position, 40.0, caster)


## Host: NACHBRAND, the last flare when the light goes out.
func _host_flare() -> void:
	if not multiplayer.is_server():
		return
	var damage: float = float(params.get("dps", 0.0)) * float(params.get("flare", 0.0))
	for box: HurtboxComponent in enemies_inside():
		box.take_hit(damage, global_position, 70.0, caster)
