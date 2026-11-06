class_name NightAtmosphere
extends Node
## The night's mood (docs/nacht_atmosphaere.md), cosmetic and local on every peer: two screen quads under the HUD, both anchored in the world.
## `night_moon.gdshader` (additive): a violet ambient wash that deepens towards the edges, pools of moonlight and glints. `night_fog.gdshader`: drifting
## violet-grey fog that the town's light pushes back. The moon has phases (eight days: new moon dim and foggy, full moon bright), a fog night (special night) brings
## heavy fog and shrinks the light, a thin mist lies over the dawn. Nothing indoors or in the mine (they have their own light).

const LIGHTS: int = 8

var fog: float = 0.0 ## 0..1, what the shader uses right now (readable for tests)
var moon: float = 0.0
var special: String = "none" ## tonight's special kind (the same pure function the NightDirector uses, so every peer agrees)

var _layer: CanvasLayer
var _fog_material: ShaderMaterial
var _moon_material: ShaderMaterial
var _special_day: int = -999999
var _origin: Vector2 = Vector2.ZERO
var _view: Vector2 = Vector2(640, 360)


func _ready() -> void:
	name = "NightAtmosphere"
	_layer = CanvasLayer.new()
	_layer.layer = 0
	add_child(_layer)
	_moon_material = _add_rect("res://assets/shaders/night_moon.gdshader")
	_fog_material = _add_rect("res://assets/shaders/night_fog.gdshader")
	RenderingServer.frame_pre_draw.connect(_push_transform) ## the camera has moved by then: reading it in _process lags a frame behind and the light would slide against the ground


func _add_rect(shader_path: String) -> ShaderMaterial:
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(shader_path) as Shader
	rect.material = material
	_layer.add_child(rect)
	return material


## Called every frame by `DayNight` (which knows whether she is indoors).
func update(indoors: bool) -> void:
	var night: float = 0.0 if indoors else TimeManager.night_amount()
	moon = TimeManager.moon_light()
	if TimeManager.day != _special_day:
		_special_day = TimeManager.day
		special = NightRules.special_for(_world_seed(), _special_day)
	var window: bool = NightRules.progress(TimeManager.time_of_day) >= 0.0
	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
	if town != null:
		town.light_scale = NightRules.light_scale(special) if window else 1.0
	var mist: float = 0.0 if indoors else 0.4 * TimeManager.dew_amount() ## the dawn: a thin mist that burns off
	fog = maxf(night * clampf(0.22 + 0.34 * (1.0 - moon) * 2.0 + NightRules.fog_boost(special), 0.0, 1.0), mist)
	_layer.visible = night > 0.003 or fog > 0.003
	if not _layer.visible:
		return
	_push_transform()
	for material: ShaderMaterial in [_moon_material, _fog_material]:
		material.set_shader_parameter("fog", fog)
	_moon_material.set_shader_parameter("night", night)
	_moon_material.set_shader_parameter("moon", moon)
	_fog_material.set_shader_parameter("night", night)
	_fog_material.set_shader_parameter("lights", _lights(town, _origin + _view * 0.5, _view.length() * 0.5))


## Hands the camera's current view (world origin and size of the screen) to both shaders. Runs right before every draw, so the pools and the fog stay nailed to the ground.
func _push_transform() -> void:
	if not is_inside_tree() or _moon_material == null:
		return
	var transform: Transform2D = get_viewport().get_canvas_transform()
	_origin = transform.affine_inverse() * Vector2.ZERO
	_view = get_viewport().get_visible_rect().size / transform.get_scale()
	for material: ShaderMaterial in [_moon_material, _fog_material]:
		material.set_shader_parameter("world_origin", _origin)
		material.set_shader_parameter("view_px", _view)


## The (up to eight) circles of light nearest to the middle of the screen that reach into it: x, y, radius.
func _lights(town: TownManager, centre: Vector2, reach: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(LIGHTS)
	if town == null or not town.founded:
		return out
	var near: Array[Vector3] = []
	for c: Vector3 in town.lit_circles():
		if Vector2(c.x, c.y).distance_to(centre) <= reach + c.z:
			near.append(c)
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return Vector2(a.x, a.y).distance_to(centre) < Vector2(b.x, b.y).distance_to(centre))
	for i: int in mini(near.size(), LIGHTS):
		out[i] = near[i]
	return out


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_push_transform):
		RenderingServer.frame_pre_draw.disconnect(_push_transform)


func _world_seed() -> int:
	var level: Node = get_parent().get_parent() if get_parent() != null else null
	var map: Variant = level.get("_map") if level != null else null
	return int(map.world_seed) if map != null else 0
