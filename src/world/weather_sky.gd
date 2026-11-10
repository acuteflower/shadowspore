class_name WeatherSky
extends Node
## The weather's picture (docs/wetter_konzept.md section 5-7), cosmetic and local on every peer: three screen quads under the HUD, all nailed to the world.
## `weather_clouds.gdshader` draws the clouds from the very field that casts their shadows, `weather_rain.gdshader` the falling rain, rain veils and mist,
## `weather_flash.gdshader` the lightning. The ground splashes, puddles and wet sheen are in ground_tone / river_water (they must lie under trees and people).
## `DayNight` calls `update` every frame after `WeatherManager.follow`. The setting WETTER-EFFEKTE (0 off, 1 reduced, 2 full) thins the layers out;
## `flash_soft` softens the lightning for people who are sensitive to flashing.

const LAYER: int = 0
const DRAW_CLOUDS: bool = false ## the clouds live in the sky, not in the picture: only their shadows and the darkness they bring reach the ground (weather_clouds.gdshader is kept for a possible high-altitude view)

var visibility: float = 0.0 ## eased: 0 indoors .. 1 outside
var slant: float = 0.15
var fall: float = 1.0
var quality: int = 2

var _layer: CanvasLayer
var _clouds: ShaderMaterial
var _rain: ShaderMaterial
var _flash: ShaderMaterial
var _clouds_rect: ColorRect
var _rain_rect: ColorRect
var _flash_rect: ColorRect
var _origin: Vector2 = Vector2.ZERO
var _view: Vector2 = Vector2(640, 360)
var _clock: float = 0.0
var _gust: float = 0.0
var _manager: WeatherManager
var _cfg: Dictionary = {}
var _tint: Color = Color(1, 1, 1)


func _ready() -> void:
	name = "WeatherSky"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_cfg = WeatherRules.cfg()
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	add_child(_layer)
	_clouds_rect = _add_rect("res://assets/shaders/weather_clouds.gdshader")
	_rain_rect = _add_rect("res://assets/shaders/weather_rain.gdshader")
	_flash_rect = _add_rect("res://assets/shaders/weather_flash.gdshader")
	_clouds = _clouds_rect.material as ShaderMaterial
	_rain = _rain_rect.material as ShaderMaterial
	_flash = _flash_rect.material as ShaderMaterial
	_flash_rect.visible = false
	RenderingServer.frame_pre_draw.connect(_push_transform) ## after the camera has moved, like the night's moon and fog
	var ld: Array = _cfg.get("light_dir", [-0.7, -0.7]) as Array
	_clouds.set_shader_parameter("light_dir", Vector2(float(ld[0]), float(ld[1])))


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_push_transform):
		RenderingServer.frame_pre_draw.disconnect(_push_transform)


func _add_rect(shader_path: String) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(shader_path) as Shader
	rect.material = material
	_layer.add_child(rect)
	return rect


## Where the flash comes from: the manager says when a bolt is struck (screen fractions), the shader draws it while `flash` is up.
func bind(manager: WeatherManager) -> void:
	_manager = manager


func update(indoors: bool, delta: float, ambient: Color) -> void:
	var w: WeatherManager = _manager if _manager != null else WeatherManager.current
	if w == null:
		return
	quality = int(GameSettings.get_value("weather_fx"))
	_clock += delta
	visibility = move_toward(visibility, 0.0 if (indoors or quality <= 0) else 1.0, delta / 0.6)
	var wind: WorldWind = WorldWind.current
	var wind_dir: Vector2 = wind.direction if wind != null else Vector2.RIGHT
	_gust = wind.gust if wind != null else 0.0
	# the rain leans with the wind: sideways drift per pixel it falls, eased so a gust bends it instead of snapping it
	var target_slant: float = clampf(wind_dir.x * (0.07 + 0.42 * w.wind + 0.10 * clampf(_gust - 0.6, 0.0, 2.0)) + wind_dir.x * 0.5 * w.storm, -1.4, 1.4)
	slant = lerpf(slant, target_slant, 1.0 - exp(-delta / 0.5))
	fall = 1.0 + 0.5 * w.storm + 0.15 * w.wind
	_push_transform()
	var reduced: float = 1.0 if quality >= 2 else 0.55
	var shown: bool = visibility > 0.01
	_clouds_rect.visible = shown and DRAW_CLOUDS
	_rain_rect.visible = shown and (w.rain > 0.01 or w.fog > 0.02 or w.local_rain > 0.01)
	if not shown:
		_flash_rect.visible = false
		return
	var night: float = TimeManager.night_amount()
	var height_cfg: Dictionary = _cfg.get("cloud_height", {}) as Dictionary
	var noon: Array = height_cfg.get("noon", [54.0, 62.0]) as Array
	var low: Array = height_cfg.get("low_sun", [104.0, 122.0]) as Array
	var gold: float = TimeManager.golden_amount()
	var height: Vector2 = Vector2(lerpf(float(noon[0]), float(low[0]), gold), lerpf(float(noon[1]), float(low[1]), gold))
	var dim: float = w.ambient_dim()
	var lit: Color = Color(ambient.r * dim, ambient.g * dim, ambient.b * dim)
	var hex: float = BiomeBlend.amount_at(w.focus)
	_tint = Color(1, 1, 1).lerp(Color(0.80, 1.0, 0.72), clampf(hex * 1.3, 0.0, 1.0))
	_clouds.set_shader_parameter("height", height)
	_clouds.set_shader_parameter("golden", gold * (1.0 - 0.6 * w.cloud))
	_clouds.set_shader_parameter("storm", w.storm)
	_clouds.set_shader_parameter("cover", w.cloud)
	_clouds.set_shader_parameter("visibility", visibility * reduced * (1.0 - 0.45 * night))
	_clouds.set_shader_parameter("clock", _clock)
	_clouds.set_shader_parameter("ambient", Vector3(lit.r, lit.g, lit.b))
	_clouds.set_shader_parameter("wind_dir", wind_dir)
	if _rain_rect.visible:
		_rain.set_shader_parameter("slant", slant)
		_rain.set_shader_parameter("fall", fall)
		_rain.set_shader_parameter("gust", clampf(_gust * 0.5, 0.0, 1.0))
		_rain.set_shader_parameter("storm", w.storm)
		_rain.set_shader_parameter("fog", w.fog * reduced)
		_rain.set_shader_parameter("visibility", visibility * (1.0 if quality >= 2 else 0.7))
		_rain.set_shader_parameter("clock", _clock)
		_rain.set_shader_parameter("ambient", Vector3(lit.r, lit.g, lit.b))
		_rain.set_shader_parameter("wind_dir", wind_dir)
		_rain.set_shader_parameter("tint", Vector3(_tint.r, _tint.g, _tint.b))
	var soft: float = 0.35 if bool(GameSettings.get_value("flash_soft")) else 1.0
	var f: float = w.flash * visibility * soft * (1.0 if quality >= 2 else 0.6)
	_flash_rect.visible = f > 0.004
	if _flash_rect.visible:
		var info: Dictionary = w.flash_info
		var color: Color = info.get("color", Color(0.8, 0.84, 1.0)) as Color
		_flash.set_shader_parameter("flash", f)
		_flash.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
		_flash.set_shader_parameter("strike", Vector2(float(info.get("x", 0.5)), float(info.get("y", 0.7))))
		_flash.set_shader_parameter("bolt", 1.0 if bool(info.get("bolt", false)) and not bool(GameSettings.get_value("flash_soft")) else 0.0)
		_flash.set_shader_parameter("bolt_seed", float(int(info.get("seed", 0)) % 997))
		_flash.set_shader_parameter("far", float(info.get("far", 0.0)))


## Hands the camera's current view to the shaders right before every draw, snapped the way the renderer snaps the picture (see NightAtmosphere).
func _push_transform() -> void:
	if not is_inside_tree() or _clouds == null:
		return
	var transform: Transform2D = get_viewport().get_canvas_transform()
	_origin = transform.affine_inverse() * Vector2.ZERO
	_view = get_viewport().get_visible_rect().size / transform.get_scale()
	var full: Transform2D = get_viewport().get_final_transform() * transform
	var snapped_origin: Vector2 = full.origin.round()
	var exact: Vector2 = Transform2D(full.x, full.y, snapped_origin).affine_inverse() * Vector2.ZERO
	if exact.is_finite() and exact.distance_squared_to(_origin) < 1.0:
		_origin = exact
	for material: ShaderMaterial in [_clouds, _rain, _flash]:
		material.set_shader_parameter("world_origin", _origin)
		material.set_shader_parameter("view_px", _view)
