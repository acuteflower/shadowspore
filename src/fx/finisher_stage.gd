class_name FinisherStage
extends ColorRect
## Finisher V2 (docs/finisher_v2_konzept.md): the local staging of a finisher for everybody who watches it (the finisher's own player and every
## local player within `stage_radius`). One quad on CanvasLayer 0 (over the world, under the HUD) with the boss intro shader
## (assets/shaders/boss_intro.gdshader): the world dusks into cold violet and the dark closes in round the pinned target (`focus`),
## thin bars of shadow smoke snap in at the apex, the plunge and the rip punch a dithered white shock, the rip flips the picture into shadow
## lightning for two frames. Audio: the buses in `duck_buses` (Music, Ambience, Weather, if they exist) are pulled down while it lasts.
## Driven by the `FinisherComponent` clock (`elapsed()`), so hit stops and the solo slow motion hold it too. Frees itself after the fade-out.

const SHADER: Shader = preload("res://assets/shaders/boss_intro.gdshader")
const BAR_PX: float = 16.0
const FADE_OUT: float = 0.32

var _finisher: FinisherComponent = null
var _target_pos: Vector2 = Vector2.ZERO
var _layer: CanvasLayer = null
var _material: ShaderMaterial = ShaderMaterial.new()
var _clock: float = 0.0
var _out: float = -1.0
var _shock: float = 0.0
var _flash: float = 0.0
var _flash_seed: float = 0.0
var _ducked: Dictionary = {} ## bus index -> dB pulled down (given back in `_restore`)
var _duck_amount: float = 0.0


## Starts the staging for `finisher` around `target_pos` (world). Returns the node (already queued into the tree).
static func play(finisher: FinisherComponent, target_pos: Vector2) -> FinisherStage:
	var stage: FinisherStage = FinisherStage.new()
	stage._finisher = finisher
	stage._target_pos = target_pos
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "FinisherStageLayer"
	layer.layer = 0 ## under the HUD (layer 1), like BossAura and HeatHaze
	stage._layer = layer
	layer.add_child(stage)
	finisher.get_tree().root.add_child(layer)
	return stage


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = SHADER
	material = _material
	color = Color.WHITE
	_flash_seed = randf() * 10.0
	_fit()
	_push()


func _exit_tree() -> void:
	_restore()


## Beat punches from the finisher: a short dithered white shock (plunge, press) or shock + shadow lightning (rip).
func punch(shock: float, flash: float = 0.0) -> void:
	_shock = maxf(_shock, shock)
	if flash > 0.0:
		_flash = maxf(_flash, flash)
		_flash_seed = randf() * 10.0


func _fit() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	if size != view:
		size = view


func _process(delta: float) -> void:
	_fit()
	var real: float = delta / maxf(Engine.time_scale, 0.05)
	_clock += real
	_shock = move_toward(_shock, 0.0, real * 7.0)
	_flash = move_toward(_flash, 0.0, real * 12.0)
	var running: bool = _finisher != null and is_instance_valid(_finisher) and _finisher.active()
	if not running and _out < 0.0:
		_out = 0.0
	if _out >= 0.0:
		_out += real
		if _out >= FADE_OUT:
			_restore()
			_layer.queue_free()
			return
	_push()


## 0..1 how far the staging is in: in over the jump, full from the apex to the rip, out over the settle (and the fade after the end).
func _amount() -> float:
	if _finisher == null or not is_instance_valid(_finisher):
		return 0.0
	var cfg: Dictionary = _finisher.config()
	var e: float = _finisher.elapsed()
	var apex: float = float(cfg.get("apex_start", 0.16))
	var settle: float = float(cfg.get("t_settle", 0.95))
	var dur: float = float(cfg.get("duration", 1.25))
	var k: float = smoothstep(0.0, apex, e) * (1.0 - smoothstep(settle, dur + 0.05, e) * 0.85)
	if _out >= 0.0:
		k *= 1.0 - clampf(_out / FADE_OUT, 0.0, 1.0)
	return k


func _bars() -> float:
	if _finisher == null or not is_instance_valid(_finisher):
		return 0.0
	var cfg: Dictionary = _finisher.config()
	var e: float = _finisher.elapsed()
	var apex: float = float(cfg.get("apex_start", 0.16))
	var settle: float = float(cfg.get("t_settle", 0.95))
	var snap: float = clampf((e - apex * 0.6) / 0.08, 0.0, 1.0)
	var bars: float = snap * (1.0 + 0.12 * sin(clampf((e - apex * 0.6) / 0.16, 0.0, 1.0) * PI)) ## the snap overshoots a little
	bars *= 1.0 - smoothstep(settle, settle + 0.25, e)
	if _out >= 0.0:
		bars *= 1.0 - clampf(_out / FADE_OUT, 0.0, 1.0)
	return bars


func _push() -> void:
	var k: float = _amount()
	var screen: Vector2 = get_viewport().get_canvas_transform() * (_target_pos + Vector2(0.0, -8.0))
	var view: Vector2 = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	_material.set_shader_parameter("view_size", view)
	_material.set_shader_parameter("time", _clock)
	_material.set_shader_parameter("night", TimeManager.night_amount())
	_material.set_shader_parameter("bars", _bars())
	_material.set_shader_parameter("bar_px", BAR_PX)
	_material.set_shader_parameter("dusk", k * 0.55)
	_material.set_shader_parameter("flash", _flash)
	_material.set_shader_parameter("flash_seed", _flash_seed)
	_material.set_shader_parameter("glitch", _flash * 0.6)
	_material.set_shader_parameter("focus", Vector2(screen.x / view.x, screen.y / view.y))
	_material.set_shader_parameter("focus_amt", k * 0.8)
	_material.set_shader_parameter("shock", _shock * 0.55)
	_material.set_shader_parameter("ring", 0.0)
	_material.set_shader_parameter("ring_on", 0.0)
	_material.set_shader_parameter("edge_heat", clampf(_shock + _flash, 0.0, 1.0))
	_duck(k)


## The world goes quiet while the moment lasts (relative offsets, given back exactly).
func _duck(k: float) -> void:
	var cfg: Dictionary = FinisherRules.settings()
	var goal: float = float(cfg.get("duck_db", -14.0)) * k
	if absf(goal - _duck_amount) < 0.05:
		return
	for bus_name: Variant in cfg.get("duck_buses", []) as Array:
		var idx: int = AudioServer.get_bus_index(StringName(String(bus_name)))
		if idx < 0:
			continue
		var prev: float = float(_ducked.get(idx, 0.0))
		AudioServer.set_bus_volume_db(idx, AudioServer.get_bus_volume_db(idx) + (goal - prev))
		_ducked[idx] = goal
	_duck_amount = goal


func _restore() -> void:
	for idx: Variant in _ducked.keys():
		var bus: int = int(idx)
		if bus < AudioServer.bus_count:
			AudioServer.set_bus_volume_db(bus, AudioServer.get_bus_volume_db(bus) - float(_ducked[idx]))
	_ducked.clear()
	_duck_amount = 0.0
