class_name Flora
extends Bush
## A bush that can do one more thing, switched on by its plants.json entry:
##  - `sun`: Sonnenwende turns its head with the sun (sheet rows 0 east, 1 up, 2 west, 3 closed for the night, 4 picked) and
##    cannot be picked while it is closed;
##  - `pull`: a root vegetable (Glutmöhre, Nachtrübe) is pulled out of the ground with Ellie's two-handed heave (`Player.begin_pull`):
##    the leaves tremble harder and harder while she braces, then it gives: a burst of earth, she is thrown back, the root pops out;
##  - `bloom: "night"`: Nebellilie is closed all day (sheet rows 0 open, 1 closed, 2 picked), opens at dusk, then sheds slow glinting
##    pollen and can be picked; by day it cannot;
##  - `puff`: Wispersaat lets go of seeds that drift away on the wind when someone brushes past (colours in the list); with
##    `puff_rise` (Funkenmohn) they are embers that shoot up and burn out quickly.

const POSE_EVERY: float = 0.5
const PUFF_COOLDOWN: float = 7.0

var _pose_wait: float = 0.0
var _row: int = -1
var _closed: bool = false ## sun flower at night, lily by day: nothing to pick
var _pollen: CPUParticles2D
var _puff_ready: float = 0.0
var _tug_from: float = -10.0 ## local: when the player here began to pull (the trembling of the leaves)

const SOIL_BURST: Array[Color] = [Color("5a4048"), Color("7a6068"), Color("3a2838")]


const WIND_LIT: Shader = preload("res://assets/shaders/flora_wind.gdshader")
const WIND_GLOW: Shader = preload("res://assets/shaders/flora_wind_glow.gdshader")
## Every small plant bends in WorldWind's wind (flora_wind.gdshader: rows above the ground slide in whole art pixels), so the
## idle skew of Bush is switched off here; rustling when someone walks through is still Bush's skew tween.
func _setup_prop() -> void:
	super()
	_sway_rate = 0.0
	_sprite.material = _wind_material(false)
	if _glow != null:
		_glow.material = _wind_material(true)


## One material per plant (cheap: the shader is shared): its own place and phase are uniforms, so the bend never depends on where the
## camera is. Walking or running must not make the plants jitter.
func _wind_material(glow: bool) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = WIND_GLOW if glow else WIND_LIT
	material.set_shader_parameter("amount", float(_spec.get("sway", 0.02)) * 60.0)
	material.set_shader_parameter("origin", global_position)
	material.set_shader_parameter("phase_seed", fposmod(global_position.x * 0.37 + global_position.y * 0.91, TAU))
	return material


## The exact row/column displacement used by flora_wind.gdshaderinc. A resident
## follows its painted leaf as well as Sprite's skew/scale (including blight).
func critter_wind_offset(at: Vector2) -> Vector2:
	var wind: WorldWind = WorldWind.current
	if not is_instance_valid(wind): return Vector2.ZERO
	var pixel: Vector2 = at - _sprite.offset
	var row: float = floorf(pixel.y)
	var column: float = pixel.x + float(_sprite.frame % _sprite.hframes) * 40.0
	var height: float = maxf(30.0 - row, 0.0) / 16.0
	var tick: float = floorf(wind.clock * 12.0) / 12.0
	var phase: float = fposmod(global_position.x * 0.37 + global_position.y * 0.91, TAU)
	var ripple: float = sin(tick * 2.4 + row * 0.11 + floorf(column / 5.0) * 1.9 + phase) * 0.35
	var amount: float = float(_spec.get("sway", 0.02)) * 60.0
	return Vector2(floorf((WorldWind.sample(global_position).x * amount + ripple) * pow(height, 1.3) + 0.5), 0.0)


func _process(delta: float) -> void:
	super(delta)
	var tug: float = (Time.get_ticks_msec() / 1000.0 - _tug_from) / Player.PULL_GRAB_TIME
	if tug >= 0.0 and tug < 1.0 and _on_screen: ## the leaves tremble more and more, then tear
		_sprite.skew = sin(tug * 70.0) * 0.03 * smoothstep(0.2, 1.0, tug) + sin(tug * 23.0) * 0.015
	if _pollen != null:
		_pollen.emitting = _on_screen and _row == 0
	if _spec.has("sun") or _spec.has("bloom"):
		_pose_wait -= delta
		if _pose_wait <= 0.0:
			_pose_wait = POSE_EVERY
			_pose()


func apply_state(new_state: Dictionary, fx: String) -> void:
	super(new_state, fx)
	if fx == "pick" and _spec.has("pull"): ## the root gives: earth flies, the hole stays
		_burst(18, SOIL_BURST, 62.0, Vector2(0, -3))
		_burst(6, _pick_colors(), 40.0, Vector2(0, -_height * 0.4))
	_row = -1
	_pose()


func interact(player: Player) -> void:
	if not _spec.has("pull"):
		super(player)
		return
	var toward: Vector2 = global_position + Vector2(0, -_radius * 0.2) - player.global_position
	_tug_from = Time.get_ticks_msec() / 1000.0
	player.begin_pull(toward.normalized(), func() -> void:
		player.add_shake(1.8)
		level.request_pick(cell))


func prompt() -> String:
	if _closed:
		return ""
	return super()


func _on_enter(body: Node2D) -> void:
	super(body)
	if _spec.has("puff") and not bool(state.get("p", 0)) and body is Player:
		_puff()


func _pose() -> void:
	if _sprite == null or not (_spec.has("sun") or _spec.has("bloom")):
		return
	var picked: bool = bool(state.get("p", 0))
	var dark: bool = TimeManager.night_amount() > (0.55 if _spec.has("sun") else 0.4) or MineManager.night_at(self, 0.0) > 0.0
	var row: int
	if _spec.has("sun"):
		var t: float = TimeManager.time_of_day
		row = 4 if picked else (3 if dark else (0 if t < 0.4 else (1 if t < 0.6 else 2)))
		_closed = row == 3
	else:
		row = 2 if picked else (0 if dark else 1)
		_closed = row == 1
	if row == _row:
		return
	_row = row
	_sprite.frame = variant + int(_spec.columns) * row
	_sync_glow(true)
	if _spec.has("bloom"):
		_set_pollen(row == 0)
	if _prompt_node != null:
		set_focused(_prompt_node.visible)


## Slow, glinting motes that rise from an open night flower (every peer, cosmetic).
func _set_pollen(on: bool) -> void:
	if on and _pollen == null:
		_pollen = CPUParticles2D.new()
		_pollen.texture = SPARKS
		_pollen.material = Unlit.material()
		var gradient: Gradient = Gradient.new()
		gradient.colors = PackedColorArray([Color("c8b8ff", 0.0), Color("c8b8ff"), Color("ffe28a"), Color("ffe28a", 0.0)])
		gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
		_pollen.color_ramp = gradient
		_pollen.amount = 5
		_pollen.lifetime = 4.5
		_pollen.direction = Vector2.UP
		_pollen.spread = 70.0
		_pollen.initial_velocity_min = 2.0
		_pollen.initial_velocity_max = 7.0
		_pollen.gravity = Vector2(4.0, -3.0)
		_pollen.damping_min = 0.5
		_pollen.damping_max = 1.5
		_pollen.scale_amount_min = 0.3
		_pollen.scale_amount_max = 0.5
		_pollen.position = Vector2(0, -_height * 0.8)
		add_child(_pollen)
	if _pollen != null:
		_pollen.emitting = on


## A few seeds lift off and float away; cosmetic, every peer does its own.
func _puff() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _puff_ready:
		return
	_puff_ready = now + PUFF_COOLDOWN
	var seeds: CPUParticles2D = CPUParticles2D.new()
	var colors: Array[Color] = _colors(_spec.puff as Array)
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(colors[0], 0.0), colors[0], colors[colors.size() - 1], Color(colors[colors.size() - 1], 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	seeds.texture = SPARKS
	seeds.material = Unlit.material()
	seeds.color_ramp = gradient
	seeds.one_shot = true
	seeds.explosiveness = 0.5
	var embers: bool = bool(_spec.get("puff_rise", false))
	seeds.amount = 14 if embers else 8
	seeds.lifetime = 1.5 if embers else 3.2
	seeds.direction = Vector2(0.3, -1.0) if embers else Vector2(0.5, -1.0)
	seeds.spread = 40.0 if embers else 55.0
	seeds.initial_velocity_min = 22.0 if embers else 8.0
	seeds.initial_velocity_max = 48.0 if embers else 20.0
	seeds.damping_min = 1.5 if embers else 3.0
	seeds.damping_max = 3.0 if embers else 5.0
	seeds.gravity = Vector2(WorldWind.sample(global_position).x * 14.0 + 5.0, -14.0 if embers else -2.0)
	seeds.scale_amount_min = 0.35
	seeds.scale_amount_max = 0.6
	seeds.position = Vector2(0, -_height * 0.8)
	seeds.emitting = true
	add_child(seeds)
	seeds.finished.connect(seeds.queue_free)
