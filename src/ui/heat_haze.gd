class_name HeatHaze
extends ColorRect
## Screen-space desert heat-mirage (`ERHITZT` / `sun_heat`), rendered on `CanvasLayer 0` over the world
## and underneath the HUD vines (`assets/shaders/heat_haze.gdshader`): rising thermal waves gently waver
## and slightly soften the air like a scorching road on a hot summer day, melting away in shade or water.

const SHADER: Shader = preload("res://assets/shaders/heat_haze.gdshader")
const FADE_IN_SPEED: float = 1.6
const FADE_OUT_SPEED: float = 2.4

var _player: Node2D
var _hud: CanvasLayer
var _layer: CanvasLayer
var _material: ShaderMaterial = ShaderMaterial.new()
var _amount: float = 0.0
var _time: float = 0.0
var _override_amount: float = -1.0


static func attach(hud: CanvasLayer, player: Node) -> HeatHaze:
	if DisplayServer.get_name() == "headless":
		return null
	var haze: HeatHaze = HeatHaze.new()
	haze.name = "HeatHaze"
	haze._hud = hud
	haze._player = player as Node2D
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "HeatHazeLayer"
	layer.layer = 0 ## over the world, underneath the HUD (layer 1) so UI text & icons stay razor-sharp
	haze._layer = layer
	layer.add_child(haze)
	hud.add_child(layer)
	return haze


func _ready() -> void:
	color = Color.WHITE
	_material.shader = SHADER
	material = _material
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	if _layer != null:
		_layer.visible = false


func set_preview_amount(value: float) -> void:
	_override_amount = value
	if value >= 0.0:
		_amount = clampf(value, 0.0, 1.0)
		_apply_shader()


func _fit() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	if size != view:
		size = view
	_material.set_shader_parameter("view_size", view)


func _target_heat() -> float:
	if _override_amount >= 0.0:
		return clampf(_override_amount, 0.0, 1.0)
	if not is_instance_valid(_player) or (_hud != null and not _hud.visible):
		return 0.0
	if _player.get("intro") != null:
		return 0.0
	var hp: HealthComponent = _player.get("health") as HealthComponent
	if hp != null and hp.current <= 0.0:
		return 0.0
	if InputManager.menu_open:
		return 0.0
	var raw_heat: float = float(_player.get("heat_amount"))
	var effects: StatusEffects = _player.get("effects") as StatusEffects
	var status_heat: float = 0.0
	if effects != null and effects.has("sun_heat"):
		status_heat = maxf(0.62, clampf(effects.scale_of("sun_heat"), 0.0, 1.0))
	var combined: float = maxf(raw_heat, status_heat)
	return smoothstep(0.28, 0.95, combined)


func _apply_shader() -> void:
	_fit()
	var active: bool = _amount > 0.003
	visible = active
	if _layer != null:
		_layer.visible = active
	if active:
		_material.set_shader_parameter("amount", _amount)
		_material.set_shader_parameter("time", _time)


func _process(delta: float) -> void:
	var want: float = _target_heat()
	var speed: float = FADE_IN_SPEED if want > _amount else FADE_OUT_SPEED
	_amount = move_toward(_amount, want, delta * speed)
	if _amount > 0.003:
		_time += delta
	_apply_shader()
